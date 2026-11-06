// Read-only Microsoft Graph pull engine. Upserts calendars, events, To Do lists
// and tasks for one account. Local-only fields are preserved on update.
import 'package:drift/drift.dart';

import '../../../data/drift/app_database.dart';
import '../../../domain/microsoft/microsoft_graph_models.dart';
import 'microsoft_graph_client.dart';

part 'microsoft_sync_engine/calendars_events.dart';
part 'microsoft_sync_engine/tasks_reconcile.dart';

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
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final calendars = await _client.listCalendars();
      final calSync = await _syncCalendars(calendars, now);
      calendarCount = calSync.count;

      eventCount = await _syncEvents(calendars, calSync.idsByRemote);

      // Task lists.
      final todoLists = await _client.listTodoLists();
      final remoteListIds = {
        for (final l in todoLists)
          if (l.id.isNotEmpty) l.id,
      };
      final listSync = await _syncTaskLists(todoLists, now);
      listCount = listSync.count;
      // Remote deletions: reconcile task lists only after a complete, successful
      // list fetch. Soft-delete lists (and their MS-synced, non-dirty tasks) that
      // disappeared from Graph. Never acts on partial/failed sync or dirty rows.
      await _reconcileDeletedTaskLists(remoteListIds, now);

      taskCount = await _syncTasks(todoLists, listSync.idsByRemote, now);

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
