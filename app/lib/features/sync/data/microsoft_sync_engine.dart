// Read-only Microsoft Graph pull engine. Upserts calendars, events, To Do lists
// and tasks for one account. Local-only fields are preserved on update.
import 'package:drift/drift.dart';

import '../../../data/drift/app_database.dart';
import 'microsoft_graph_client.dart';

class MicrosoftSyncResult {
  const MicrosoftSyncResult({
    required this.calendars,
    required this.events,
    required this.taskLists,
    required this.tasks,
    required this.authFailure,
  });

  final int calendars;
  final int events;
  final int taskLists;
  final int tasks;
  final bool authFailure;
}

class MicrosoftSyncEngine {
  MicrosoftSyncEngine(
    this._db,
    this._client,
    this.account, {
    DateTime? windowStart,
    DateTime? windowEnd,
  }) : _windowStart =
           (windowStart ??
                   DateTime.now().toUtc().subtract(const Duration(days: 30)))
               .toUtc(),
       _windowEnd =
           (windowEnd ?? DateTime.now().toUtc().add(const Duration(days: 90)))
               .toUtc();

  final AppDatabase _db;
  final MicrosoftGraphClient _client;
  final String account;
  final DateTime _windowStart;
  final DateTime _windowEnd;

  bool _authFailure = false;
  bool get authFailure => _authFailure;

  Future<MicrosoftSyncResult> syncNow() async {
    _authFailure = false;
    var calendarCount = 0;
    var eventCount = 0;
    var listCount = 0;
    var taskCount = 0;
    try {
      final calendars = await _client.listCalendars();
      final calendarIdByRemote = <String, String>{};
      calendarCount = 0;
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      for (final c in calendars) {
        final remoteId = c.id;
        if (remoteId.isEmpty) continue;
        final existing =
            await (_db.select(_db.calendars)..where(
                  (t) =>
                      t.source.equals('microsoft') &
                      t.microsoftAccount.equals(account) &
                      t.remoteId.equals(remoteId),
                ))
                .getSingleOrNull();
        if (existing == null) {
          final id = 'mscal_${account}_$remoteId';
          await _db
              .into(_db.calendars)
              .insert(
                CalendarsCompanion.insert(
                  id: id,
                  remoteId: Value(remoteId),
                  name: c.name.isEmpty ? remoteId : c.name,
                  color: Value(c.hexColor),
                  source: const Value('microsoft'),
                  microsoftAccount: Value(account),
                  readOnly: Value(!c.canEdit),
                  enabled: const Value(true),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
          calendarIdByRemote[remoteId] = id;
          calendarCount++;
        } else {
          await (_db.update(
            _db.calendars,
          )..where((t) => t.id.equals(existing.id))).write(
            CalendarsCompanion(
              name: Value(c.name.isEmpty ? existing.name : c.name),
              color: Value(c.hexColor ?? existing.color),
              readOnly: Value(!c.canEdit),
              microsoftAccount: Value(account),
              dirty: const Value(false),
              updatedAt: Value(now),
            ),
          );
          calendarIdByRemote[remoteId] = existing.id;
        }
      }

      eventCount = 0;
      for (final cal in calendars) {
        final localCalId = calendarIdByRemote[cal.id];
        if (localCalId == null) continue;
        final events = await _client.calendarView(
          _windowStart,
          _windowEnd,
          calendarId: cal.id,
        );
        for (final e in events) {
          final remoteId = e.id;
          if (remoteId.isEmpty) continue;
          final existing =
              await (_db.select(_db.events)..where(
                    (t) =>
                        t.microsoftAccount.equals(account) &
                        t.remoteId.equals(remoteId),
                  ))
                  .getSingleOrNull();
          final isAllDay = e.isAllDay;
          final startUtc = e.start?.utc;
          final endUtc = e.end?.utc;
          final startDate = isAllDay && startUtc != null
              ? _dateStr(startUtc)
              : null;
          final endDate = isAllDay && endUtc != null ? _dateStr(endUtc) : null;
          final title = e.subject ?? '';
          final cancelled = e.isCancelled;
          final status = cancelled ? 'cancelled' : 'confirmed';
          final meetUrl = e.onlineMeetingUrl;
          final location = e.location?.displayName;
          final notes = e.bodyPreview;
          final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
          if (existing == null) {
            await _db
                .into(_db.events)
                .insert(
                  EventsCompanion.insert(
                    id: 'msevt_${account}_$remoteId',
                    calendarId: localCalId,
                    title: Value(title),
                    notes: Value(notes),
                    location: Value(location),
                    startUtc: Value(
                      isAllDay ? null : startUtc?.millisecondsSinceEpoch,
                    ),
                    endUtc: Value(
                      isAllDay ? null : endUtc?.millisecondsSinceEpoch,
                    ),
                    startDate: Value(startDate),
                    endDate: Value(endDate),
                    isAllDay: Value(isAllDay),
                    status: Value(status),
                    meetUrl: Value(meetUrl),
                    microsoftAccount: Value(account),
                    remoteId: Value(remoteId),
                    dirty: const Value(false),
                    createdAt: nowMs,
                    updatedAt: nowMs,
                  ),
                );
            eventCount++;
          } else {
            await (_db.update(
              _db.events,
            )..where((t) => t.id.equals(existing.id))).write(
              EventsCompanion(
                calendarId: Value(localCalId),
                title: Value(title),
                notes: Value(notes ?? existing.notes),
                location: Value(location ?? existing.location),
                startUtc: Value(
                  isAllDay ? null : startUtc?.millisecondsSinceEpoch,
                ),
                endUtc: Value(isAllDay ? null : endUtc?.millisecondsSinceEpoch),
                startDate: Value(startDate),
                endDate: Value(endDate),
                isAllDay: Value(isAllDay),
                status: Value(status),
                meetUrl: Value(meetUrl ?? existing.meetUrl),
                microsoftAccount: Value(account),
                remoteId: Value(remoteId),
                dirty: const Value(false),
                updatedAt: Value(nowMs),
                // Preserve local-only fields.
                alarmPreset: Value(existing.alarmPreset),
                reminders: Value(existing.reminders),
                visibility: Value(existing.visibility),
                createMeet: Value(existing.createMeet),
                colorId: Value(existing.colorId),
              ),
            );
            eventCount++;
          }
          // TODO(#issue): map Graph recurrence to RRULE when representable; for now store occurrence as single event.
        }
      }

      // Task lists.
      final todoLists = await _client.listTodoLists();
      final listIdByRemote = <String, String>{};
      listCount = 0;
      for (final l in todoLists) {
        final remoteId = l.id;
        if (remoteId.isEmpty) continue;
        final existing =
            await (_db.select(_db.taskLists)..where(
                  (t) =>
                      t.microsoftAccount.equals(account) &
                      t.remoteId.equals(remoteId),
                ))
                .getSingleOrNull();
        if (existing == null) {
          final id = 'mstl_${account}_$remoteId';
          await _db
              .into(_db.taskLists)
              .insert(
                TaskListsCompanion.insert(
                  id: id,
                  remoteId: Value(remoteId),
                  name: l.displayName.isEmpty ? remoteId : l.displayName,
                  color: const Value(null),
                  microsoftAccount: Value(account),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
          listIdByRemote[remoteId] = id;
          listCount++;
        } else {
          await (_db.update(
            _db.taskLists,
          )..where((t) => t.id.equals(existing.id))).write(
            TaskListsCompanion(
              name: Value(
                l.displayName.isEmpty ? existing.name : l.displayName,
              ),
              microsoftAccount: Value(account),
              dirty: const Value(false),
              updatedAt: Value(now),
            ),
          );
          listIdByRemote[remoteId] = existing.id;
        }
      }

      taskCount = 0;
      for (final l in todoLists) {
        final remoteListId = l.id;
        if (remoteListId.isEmpty) continue;
        final localListId = listIdByRemote[remoteListId];
        if (localListId == null) continue;
        final tasks = await _client.listTodoTasks(remoteListId);
        for (final t in tasks) {
          final remoteId = t.id;
          if (remoteId.isEmpty) continue;
          final existing =
              await (_db.select(_db.tasks)..where(
                    (x) =>
                        x.microsoftAccount.equals(account) &
                        x.remoteId.equals(remoteId),
                  ))
                  .getSingleOrNull();
          final dueUtc = t.dueDateTime?.utc;
          final dueDate = dueUtc != null ? _dateStr(dueUtc) : null;
          final dueTime = dueUtc != null
              ? dueUtc.hour * 60 + dueUtc.minute
              : null;
          final completedAt = (t.status == 'completed')
              ? t.completedDateTime?.utc?.millisecondsSinceEpoch
              : null;
          final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
          if (existing == null) {
            await _db
                .into(_db.tasks)
                .insert(
                  TasksCompanion.insert(
                    id: 'mstask_${account}_$remoteId',
                    listId: Value(localListId),
                    title: Value(t.title),
                    notes: Value(t.body),
                    dueDate: Value(dueDate),
                    dueTime: Value(dueTime),
                    completedAt: Value(completedAt),
                    microsoftAccount: Value(account),
                    remoteId: Value(remoteId),
                    dirty: const Value(false),
                    createdAt: nowMs,
                    updatedAt: nowMs,
                  ),
                );
            taskCount++;
          } else {
            await (_db.update(
              _db.tasks,
            )..where((x) => x.id.equals(existing.id))).write(
              TasksCompanion(
                listId: Value(localListId),
                title: Value(t.title),
                notes: Value(t.body),
                dueDate: Value(dueDate),
                dueTime: Value(dueTime),
                completedAt: Value(completedAt),
                microsoftAccount: Value(account),
                remoteId: Value(remoteId),
                dirty: const Value(false),
                updatedAt: Value(nowMs),
                // Preserve local-only fields.
                plannedDate: Value(existing.plannedDate),
                plannedStart: Value(existing.plannedStart),
                plannedEnd: Value(existing.plannedEnd),
                seriesId: Value(existing.seriesId),
                recurrenceKey: Value(existing.recurrenceKey),
                priority: Value(existing.priority),
                durationMin: Value(existing.durationMin),
                rrule: Value(existing.rrule),
                repeatMode: Value(existing.repeatMode),
                pinned: Value(existing.pinned),
                wontDo: Value(existing.wontDo),
                alarmPreset: Value(existing.alarmPreset),
                reminders: Value(existing.reminders),
              ),
            );
            taskCount++;
          }
        }
      }

      return MicrosoftSyncResult(
        calendars: calendarCount,
        events: eventCount,
        taskLists: listCount,
        tasks: taskCount,
        authFailure: false,
      );
    } on MicrosoftGraphException catch (e) {
      if (e.isUnauthorized || e.isForbidden) {
        _authFailure = true;
        return MicrosoftSyncResult(
          calendars: calendarCount,
          events: eventCount,
          taskLists: listCount,
          tasks: taskCount,
          authFailure: true,
        );
      }
      rethrow;
    }
  }

  String _dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
