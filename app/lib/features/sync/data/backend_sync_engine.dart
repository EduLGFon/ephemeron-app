// Backend changeset sync for habits and focus (single-flight).
// Offline-first: dirty-flag + updatedAt-cursor push (batch 200), LWW pull
// that never overwrites locally dirty rows. Google data never enters here:
// only habit/focus tables are read and written.
import 'package:drift/drift.dart';

import '../../../data/drift/app_database.dart';
import '../../../data/remote/backend_api_client.dart';
import '../../../data/remote/backend_sync_api.dart';
import '../../auth/data/backend_auth.dart';
import 'sync_engine.dart' show SyncStatus;

class BackendSyncEngine {
  BackendSyncEngine(
    this._db,
    this._auth, {
    BackendSyncApi? Function(Future<String?> Function() accessToken)?
    apiFactory,
  }) : _apiFactory = apiFactory;

  final AppDatabase _db;
  final BackendAuth _auth;
  final BackendSyncApi? Function(Future<String?> Function() accessToken)?
  _apiFactory;
  bool _running = false;
  SyncStatus _status = SyncStatus.synced;
  String? _lastError;

  SyncStatus get status => _status;
  String? get lastError => _lastError;

  static const int batchLimit = 200;
  static const String _logsCursorKey = 'backend.logsCursor';
  static const String _focusCursorKey = 'backend.focusCursor';
  static const String _pullCursorKey = 'backend.pullCursor';

  int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  /// Pulls remote deltas, then pushes local changes. Single-flight.
  /// Pull runs first so locally dirty rows win until they are pushed.
  Future<void> syncNow() async {
    if (_running) return;
    _running = true;
    _status = SyncStatus.syncing;
    try {
      final api = _apiFactory?.call(_auth.accessToken);
      if (api == null) {
        _status = SyncStatus.offline;
        return;
      }
      final token = await _auth.accessToken();
      if (token == null) {
        _status = SyncStatus.offline;
        return;
      }
      await _pull(api);
      await _push(api);
      await _setSyncValue('backend.lastSyncAt', _now().toString());
      _status = SyncStatus.synced;
      _lastError = null;
    } on BackendApiException catch (e) {
      _status = SyncStatus.error;
      _lastError = 'backend ${e.status}';
    } catch (_) {
      _status = SyncStatus.error;
      _lastError = 'sync failed';
    } finally {
      _running = false;
    }
  }

  Future<void> _push(BackendSyncApi api) async {
    final dirtyHabits =
        await (_db.select(_db.habits)
              ..where((h) => h.dirty.equals(true))
              ..orderBy([(h) => OrderingTerm.asc(h.updatedAt)])
              ..limit(batchLimit))
            .get();
    final logsCursor = await _cursor(_logsCursorKey);
    final dirtyLogs =
        await (_db.select(_db.habitLogs)
              ..where((l) => l.updatedAt.isBiggerThanValue(logsCursor))
              ..orderBy([(l) => OrderingTerm.asc(l.updatedAt)])
              ..limit(batchLimit))
            .get();
    final focusCursor = await _cursor(_focusCursorKey);
    final dirtyFocus =
        await (_db.select(_db.focusSessions)
              ..where((f) => f.updatedAt.isBiggerThanValue(focusCursor))
              ..orderBy([(f) => OrderingTerm.asc(f.updatedAt)])
              ..limit(batchLimit))
            .get();
    if (dirtyHabits.isEmpty && dirtyLogs.isEmpty && dirtyFocus.isEmpty) return;

    await api.push(
      habits: [for (final h in dirtyHabits) _habitJson(h)],
      habitLogs: [for (final l in dirtyLogs) _logJson(l)],
      focusSessions: [for (final f in dirtyFocus) _focusJson(f)],
    );

    if (dirtyHabits.isNotEmpty) {
      final maxTs = dirtyHabits
          .map((h) => h.updatedAt)
          .reduce((a, b) => a > b ? a : b);
      final ids = dirtyHabits.map((h) => h.id).toList();
      await (_db.update(_db.habits)..where(
            (h) => h.id.isIn(ids) & h.updatedAt.isSmallerOrEqualValue(maxTs),
          ))
          .write(const HabitsCompanion(dirty: Value(false)));
      for (final id in ids) {
        await (_db.delete(_db.outbox)..where(
              (o) =>
                  (o.entity.equals('habit') & o.entityId.equals(id)) |
                  o.entity.equals('habit_log:$id'),
            ))
            .go();
      }
    }
    if (dirtyLogs.isNotEmpty) {
      await _setCursor(
        _logsCursorKey,
        dirtyLogs.map((l) => l.updatedAt).reduce((a, b) => a > b ? a : b),
      );
    }
    if (dirtyFocus.isNotEmpty) {
      await _setCursor(
        _focusCursorKey,
        dirtyFocus.map((f) => f.updatedAt).reduce((a, b) => a > b ? a : b),
      );
    }
  }

  Future<void> _pull(BackendSyncApi api) async {
    final since = await _cursor(_pullCursorKey);
    final pulled = await api.pull(since);
    var maxTs = since;
    int tsOf(Map<String, dynamic> m) => (m['updatedAt'] as int?) ?? 0;

    for (final m in pulled.habits) {
      final ts = tsOf(m);
      if (ts > maxTs) maxTs = ts;
      await _mergeHabit(m);
    }
    var maxLogTs = await _cursor(_logsCursorKey);
    var maxFocusTs = await _cursor(_focusCursorKey);
    for (final m in pulled.habitLogs) {
      final ts = tsOf(m);
      if (ts > maxTs) maxTs = ts;
      if (ts > maxLogTs) maxLogTs = ts;
      await _mergeLog(m);
    }
    for (final m in pulled.focusSessions) {
      final ts = tsOf(m);
      if (ts > maxTs) maxTs = ts;
      if (ts > maxFocusTs) maxFocusTs = ts;
      await _mergeFocus(m);
    }
    // Pulled rows are in sync; do not echo them back on the next push.
    await _setCursor(_logsCursorKey, maxLogTs);
    await _setCursor(_focusCursorKey, maxFocusTs);
    if (maxTs > since) await _setCursor(_pullCursorKey, maxTs);
  }

  /// LWW merge that never overwrites locally dirty rows or newer rows.
  Future<void> _mergeHabit(Map<String, dynamic> m) async {
    final id = m['id'] as String?;
    if (id == null) return;
    final existing = await (_db.select(
      _db.habits,
    )..where((h) => h.id.equals(id))).getSingleOrNull();
    if (existing != null &&
        (existing.dirty ||
            existing.updatedAt >= (m['updatedAt'] as int? ?? 0))) {
      return;
    }
    final sectionId = m['sectionId'] as String?;
    final sectionOk =
        sectionId == null ||
        await (_db.select(
              _db.habitSections,
            )..where((s) => s.id.equals(sectionId))).getSingleOrNull() !=
            null;
    final companion = HabitsCompanion(
      id: Value(id),
      sectionId: Value(sectionOk ? sectionId : null),
      name: Value((m['name'] as String?) ?? 'Habit'),
      frequency: Value((m['frequency'] as String?) ?? 'daily'),
      weekdaysMask: Value((m['weekdaysMask'] as int?) ?? 0),
      weeklyTarget: Value(m['weeklyTarget'] as int?),
      intervalDays: Value(m['intervalDays'] as int?),
      goalType: Value(m['goalType'] as String?),
      goalAmount: Value((m['goalAmount'] as num?)?.toDouble()),
      unit: Value(m['unit'] as String?),
      increment: Value((m['increment'] as num?)?.toDouble()),
      goalDurationDays: Value(m['goalDurationDays'] as int?),
      startDate: Value(m['startDate'] as String?),
      archived: Value((m['archived'] as bool?) ?? false),
      reminderTime: Value(m['reminderTime'] as String?),
      alarmPreset: Value(m['alarmPreset'] as String?),
      createdAt: Value((m['createdAt'] as int?) ?? _now()),
      updatedAt: Value((m['updatedAt'] as int?) ?? _now()),
      deletedAt: Value(m['deletedAt'] as int?),
      dirty: const Value(false),
    );
    await _db.into(_db.habits).insertOnConflictUpdate(companion);
  }

  Future<void> _mergeLog(Map<String, dynamic> m) async {
    final habitId = m['habitId'] as String?;
    final dayKey = m['dayKey'] as String?;
    if (habitId == null || dayKey == null) return;
    final habit = await (_db.select(
      _db.habits,
    )..where((h) => h.id.equals(habitId))).getSingleOrNull();
    if (habit == null) return;
    final existing =
        await (_db.select(_db.habitLogs)..where(
              (l) => l.habitId.equals(habitId) & l.dayKey.equals(dayKey),
            ))
            .getSingleOrNull();
    final ts = (m['updatedAt'] as int?) ?? 0;
    if (existing != null && existing.updatedAt >= ts) return;
    if (existing == null) {
      await _db
          .into(_db.habitLogs)
          .insert(
            HabitLogsCompanion.insert(
              id: m['id'] as String? ?? '$habitId@$dayKey',
              habitId: habitId,
              dayKey: dayKey,
              amount: Value((m['amount'] as num?)?.toDouble() ?? 0),
              done: Value((m['done'] as bool?) ?? false),
              skipped: Value((m['skipped'] as bool?) ?? false),
              createdAt: (m['createdAt'] as int?) ?? _now(),
              updatedAt: ts,
            ),
          );
    } else {
      await (_db.update(
        _db.habitLogs,
      )..where((l) => l.id.equals(existing.id))).write(
        HabitLogsCompanion(
          amount: Value((m['amount'] as num?)?.toDouble() ?? 0),
          done: Value((m['done'] as bool?) ?? false),
          skipped: Value((m['skipped'] as bool?) ?? false),
          updatedAt: Value(ts),
        ),
      );
    }
  }

  Future<void> _mergeFocus(Map<String, dynamic> m) async {
    final id = m['id'] as String?;
    if (id == null) return;
    final ts = (m['updatedAt'] as int?) ?? 0;
    final existing = await (_db.select(
      _db.focusSessions,
    )..where((f) => f.id.equals(id))).getSingleOrNull();
    if (existing != null && existing.updatedAt >= ts) return;
    await _db
        .into(_db.focusSessions)
        .insertOnConflictUpdate(
          FocusSessionsCompanion(
            id: Value(id),
            taskId: Value(m['taskId'] as String?),
            habitId: Value(m['habitId'] as String?),
            startUtc: Value((m['startUtc'] as int?) ?? ts),
            endUtc: Value(m['endUtc'] as int?),
            targetEndUtc: Value(m['targetEndUtc'] as int?),
            phase: Value(m['phase'] as String?),
            note: Value(m['note'] as String?),
            createdAt: Value((m['createdAt'] as int?) ?? _now()),
            updatedAt: Value(ts),
          ),
        );
  }

  Map<String, dynamic> _habitJson(Habit h) => {
    'id': h.id,
    'sectionId': h.sectionId,
    'name': h.name,
    'frequency': h.frequency,
    'weekdaysMask': h.weekdaysMask,
    'weeklyTarget': h.weeklyTarget,
    'intervalDays': h.intervalDays,
    'goalType': h.goalType,
    'goalAmount': h.goalAmount,
    'unit': h.unit,
    'increment': h.increment,
    'goalDurationDays': h.goalDurationDays,
    'startDate': h.startDate,
    'archived': h.archived,
    'reminderTime': h.reminderTime,
    'alarmPreset': h.alarmPreset,
    'createdAt': h.createdAt,
    'updatedAt': h.updatedAt,
    'deletedAt': h.deletedAt,
  };

  Map<String, dynamic> _logJson(HabitLog l) => {
    'id': l.id,
    'habitId': l.habitId,
    'dayKey': l.dayKey,
    'amount': l.amount,
    'done': l.done,
    'skipped': l.skipped,
    'createdAt': l.createdAt,
    'updatedAt': l.updatedAt,
  };

  Map<String, dynamic> _focusJson(FocusSession f) => {
    'id': f.id,
    'taskId': f.taskId,
    'habitId': f.habitId,
    'startUtc': f.startUtc,
    'endUtc': f.endUtc,
    'targetEndUtc': f.targetEndUtc,
    'phase': f.phase,
    'note': f.note,
    'createdAt': f.createdAt,
    'updatedAt': f.updatedAt,
  };

  Future<int> _cursor(String key) async {
    final row = await (_db.select(
      _db.syncState,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return int.tryParse(row?.value ?? '') ?? 0;
  }

  Future<void> _setCursor(String key, int value) =>
      _setSyncValue(key, value.toString());

  Future<void> _setSyncValue(String key, String value) async {
    await _db
        .into(_db.syncState)
        .insertOnConflictUpdate(
          SyncStateCompanion.insert(
            key: key,
            value: Value(value),
            lastSyncAt: Value(_now()),
          ),
        );
  }
}
