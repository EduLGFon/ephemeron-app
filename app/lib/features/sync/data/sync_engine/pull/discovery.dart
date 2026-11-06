part of '../../sync_engine.dart';

extension on SyncEngine {
  // Discovery: mirror the remote calendar/task-list catalog locally so
  // the first sync after sign-in has something to pull into. Local-only
  // rows are never touched; renamed remotes update in place when clean.

  Future<(int, int)> _syncCalendarList(GoogleApiClient client) async {
    final remote = await client.calendarList();
    debugPrint('[sync] calendarList returned ${remote.length} items');
    _accountCalendarIds = account == null
        ? null
        : {
            for (final c in remote) c['id'] as String?,
          }.whereType<String>().toSet();
    final now = _now();
    var created = 0;
    for (final c in remote) {
      final id = c['id'] as String?;
      if (id == null || c['deleted'] == true) continue;
      final name = (c['summary'] as String?)?.trim();
      var existing = await (_db.select(
        _db.calendars,
      )..where((t) => t.remoteId.equals(id))).getSingleOrNull();
      // Repair legacy rows created before remoteId was persisted.
      if (existing == null && name != null && name.isNotEmpty) {
        existing =
            await (_db.select(_db.calendars)..where(
                  (t) =>
                      t.source.equals('google') &
                      t.remoteId.isNull() &
                      t.name.equals(name),
                ))
                .getSingleOrNull();
        if (existing != null) {
          await (_db.update(
            _db.calendars,
          )..where((t) => t.id.equals(existing!.id))).write(
            CalendarsCompanion(
              remoteId: Value(id),
              updatedAt: Value(now),
              googleAccount: Value(account),
            ),
          );
          debugPrint(
            '[sync] repaired legacy calendar remoteId id=${existing.id}',
          );
        }
      }
      if (existing == null) {
        await _db
            .into(_db.calendars)
            .insert(
              CalendarsCompanion.insert(
                id: newId(),
                remoteId: Value(id),
                name: (name == null || name.isEmpty) ? id : name,
                color: Value(_calendarColorOf(c)),
                source: const Value('google'),
                googleAccount: Value(account),
                readOnly: Value((c['accessRole'] as String?) == 'reader'),
                createdAt: now,
                updatedAt: now,
              ),
            );
        created++;
      } else {
        // Keep the ownership stamp current: a remote id belongs to exactly
        // one account (shared calendars may flap; either token can pull).
        if (account != null && existing.googleAccount != account) {
          await (_db.update(
            _db.calendars,
          )..where((t) => t.id.equals(existing!.id))).write(
            CalendarsCompanion(
              googleAccount: Value(account),
              updatedAt: Value(now),
            ),
          );
        }
        if (!existing.dirty && name != null && name.isNotEmpty) {
          final color = _calendarColorOf(c);
          final update = CalendarsCompanion(
            name: Value(name),
            updatedAt: Value(now),
            color: color == null ? const Value.absent() : Value(color),
          );
          if (existing.name != name || existing.color != color) {
            await (_db.update(
              _db.calendars,
            )..where((t) => t.id.equals(existing!.id))).write(update);
          }
        }
      }
    }
    // Remove duplicate google calendars left by earlier (buggy) runs.
    final all = await (_db.select(
      _db.calendars,
    )..where((c) => c.source.equals('google'))).get();
    final seen = <String>{};
    for (final c in all) {
      final key = c.remoteId;
      if (key == null) continue;
      if (seen.contains(key)) {
        await (_db.delete(_db.calendars)..where((x) => x.id.equals(c.id))).go();
      } else {
        seen.add(key);
      }
    }
    // Disable calendars of THIS account that are no longer reachable, but
    // only when the remote list is non-empty (an empty result is ambiguous).
    // Never touch another account's rows: their loop owns them.
    if (remote.isNotEmpty && account != null) {
      final remoteIds = {for (final c in remote) c['id'] as String?}
        ..removeWhere((x) => x == null);
      for (final c in all) {
        if (c.googleAccount == account &&
            c.remoteId != null &&
            !remoteIds.contains(c.remoteId)) {
          await (_db.update(_db.calendars)..where((x) => x.id.equals(c.id)))
              .write(const CalendarsCompanion(enabled: Value(false)));
        }
      }
    }
    return (remote.length, created);
  }

  Future<(int, int)> _syncTaskLists(GoogleApiClient client) async {
    final remote = await client.taskLists();
    debugPrint('[sync] taskLists returned ${remote.length} items');
    _accountListIds = account == null
        ? null
        : {
            for (final l in remote) l['id'] as String?,
          }.whereType<String>().toSet();
    final now = _now();
    var created = 0;
    for (final l in remote) {
      final id = l['id'] as String?;
      if (id == null) continue;
      final name = (l['title'] as String?)?.trim();
      // A remote id belongs to exactly one local row. Duplicate rows from
      // older runs must not make discovery throw or insert another copy.
      final linked = await (_db.select(
        _db.taskLists,
      )..where((t) => t.remoteId.equals(id))).get();
      final existing = linked.where((row) => row.deletedAt == null).firstOrNull;
      if (existing == null) {
        if (linked.isNotEmpty) {
          // The only local copy is a tombstone awaiting remote delete. Do not
          // resurrect it; the queued delete (or the next sync) owns it.
          continue;
        }
        await _db
            .into(_db.taskLists)
            .insert(
              TaskListsCompanion.insert(
                id: newId(),
                remoteId: Value(id),
                name: (name == null || name.isEmpty) ? id : name,
                googleAccount: Value(account),
                createdAt: now,
                updatedAt: now,
              ),
            );
        created++;
      } else {
        if (account != null && existing.googleAccount != account) {
          await (_db.update(
            _db.taskLists,
          )..where((t) => t.id.equals(existing.id))).write(
            TaskListsCompanion(
              googleAccount: Value(account),
              updatedAt: Value(now),
            ),
          );
        }
        if (!existing.dirty && name != null && name.isNotEmpty) {
          await (_db.update(
            _db.taskLists,
          )..where((t) => t.id.equals(existing.id))).write(
            TaskListsCompanion(name: Value(name), updatedAt: Value(now)),
          );
        }
      }
    }
    return (remote.length, created);
  }

  /// Google calendarList color: backgroundColor hex wins, colorId palette
  /// id as fallback. Returns null when the entry carries no color so the
  /// occurrence builder can apply its stable per-calendar fallback.
  String? _calendarColorOf(Map<String, dynamic> c) {
    final bg = c['backgroundColor'] as String?;
    if (bg != null && bg.isNotEmpty) return bg;
    final id = c['colorId'] as String?;
    if (id != null && id.isNotEmpty) return id;
    return null;
  }
}
