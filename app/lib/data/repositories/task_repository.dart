// Task, list, tag and smart-list repository. Drift/local only.
// Every mutation writes optimistically and enqueues an outbox row;
// the user never waits on the network.
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/core/search/sanitize.dart';
import 'package:ephemeron/core/time/time.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/outbox_helper.dart';
import 'package:ephemeron/data/repositories/pending_operations_repository.dart';
import 'package:ephemeron/data/services/alarm_cancel.dart';
import 'package:ephemeron/domain/sources/source_move.dart';
import 'package:ephemeron/domain/tasks/recurring_task.dart';
import 'package:ephemeron/domain/tasks/smart_filter.dart';

part 'task_repository/lists.dart';
part 'task_repository/tasks.dart';
part 'task_repository/completion.dart';
part 'task_repository/occurrences.dart';
part 'task_repository/queries.dart';
part 'task_repository/move.dart';
part 'task_repository/tags.dart';
part 'task_repository/smart_lists.dart';
part 'task_repository/trash.dart';

class _TaskRepositoryBase {
  _TaskRepositoryBase(this._db);

  final AppDatabase _db;

  Future<void> _enqueue(
    String entity,
    String entityId,
    String op, {
    String? payload,
  }) => enqueueOutbox(
    _db,
    entity: entity,
    entityId: entityId,
    op: op,
    payload: payload,
  );

  Future<void> _enqueueRemoteDelete({
    required String taskId,
    required String listRemoteId,
    required String taskRemoteId,
    required String account,
  }) {
    return enqueueOutbox(
      _db,
      entity: 'task_remote',
      entityId: taskId,
      op: 'delete',
      payload: jsonEncode({
        'account': account,
        'listRemoteId': listRemoteId,
        'taskRemoteId': taskRemoteId,
      }),
    );
  }

  Future<String?> _defaultListId() async {
    final lists =
        await (_db.select(_db.taskLists)
              ..where((l) => l.deletedAt.isNull())
              ..orderBy([(l) => OrderingTerm.asc(l.sortOrder)])
              ..limit(1))
            .get();
    return lists.isEmpty ? null : lists.single.id;
  }

  Future<String?> _accountOfList(String? listId) async {
    if (listId == null) return null;
    return (await _list(listId))?.googleAccount;
  }

  Future<TaskList?> _list(String listId) {
    return (_db.select(
      _db.taskLists,
    )..where((l) => l.id.equals(listId))).getSingleOrNull();
  }

  String _like(String query) => '%${sanitizeSearch(query)}%';

  bool _blank(String query) => sanitizeSearch(query).trim().isEmpty;

  String _effectiveOccurrenceDate({
    String? plannedStart,
    String? plannedDate,
    String? dueDate,
  }) {
    if (plannedStart != null && plannedStart.length >= 10) {
      return plannedStart.substring(0, 10);
    }
    if (plannedDate != null) return plannedDate;
    if (dueDate != null) return dueDate;
    return dateKey(DateTime.now());
  }

  DateTime _parseDateKey(String value) {
    final p = value.split('-');
    return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  DateTime _taskBaseUtcForDate(DateTime d) {
    return DateTime.utc(d.year, d.month, d.day, d.hour, d.minute);
  }

  String _formatLocalIso(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}T'
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
  String _shiftBaseDate(Task task) => task.dueDate ?? _baseDateKey(task);

  String? _shiftPlannedDate(
    String? plannedDate,
    String? dueDate,
    DateTime nextDue,
  ) {
    if (plannedDate == null || dueDate == null) return plannedDate;
    final nextKey = dateKey(nextDue);
    final deltaDays = _parseDateKey(
      nextKey,
    ).difference(_parseDateKey(dueDate)).inDays;
    final p = plannedDate.split('-');
    return dateKey(
      DateTime.utc(
        int.parse(p[0]),
        int.parse(p[1]),
        int.parse(p[2]) + deltaDays,
      ),
    );
  }

  String? _shiftPlannedStart(
    String? plannedStart,
    String? dueDate,
    DateTime nextDue,
  ) {
    if (plannedStart == null || dueDate == null) return plannedStart;
    final nextKey = dateKey(nextDue);
    final deltaDays = _parseDateKey(
      nextKey,
    ).difference(_parseDateKey(dueDate)).inDays;
    final dt = DateTime.parse(plannedStart);
    final shifted = DateTime(
      dt.year,
      dt.month,
      dt.day + deltaDays,
      dt.hour,
      dt.minute,
    );
    return _formatLocalIso(shifted);
  }

  String? _shiftPlannedEnd(
    String? plannedEnd,
    String? dueDate,
    DateTime nextDue,
  ) {
    if (plannedEnd == null || dueDate == null) return plannedEnd;
    final nextKey = dateKey(nextDue);
    final deltaDays = _parseDateKey(
      nextKey,
    ).difference(_parseDateKey(dueDate)).inDays;
    final dt = DateTime.parse(plannedEnd);
    final shifted = DateTime(
      dt.year,
      dt.month,
      dt.day + deltaDays,
      dt.hour,
      dt.minute,
    );
    return _formatLocalIso(shifted);
  }

  Future<bool> _hasSiblingOccurrence(
    String seriesId,
    String occurrenceDate,
  ) async {
    final rows =
        await (_db.select(_db.tasks)..where(
              (t) =>
                  t.seriesId.equals(seriesId) &
                  t.recurrenceKey.equals(occurrenceDate) &
                  t.deletedAt.isNull(),
            ))
            .get();
    return rows.isNotEmpty;
  }

  DateTime _taskBaseUtc(Task task) {
    if (task.dueDate != null) {
      final p = task.dueDate!.split('-');
      final mins = task.dueTime ?? 0;
      return DateTime.utc(
        int.parse(p[0]),
        int.parse(p[1]),
        int.parse(p[2]),
        mins ~/ 60,
        mins % 60,
      );
    }
    if (task.plannedStart != null && task.plannedStart!.isNotEmpty) {
      return DateTime.parse(task.plannedStart!).toUtc();
    }
    if (task.plannedDate != null) {
      final p = task.plannedDate!.split('-');
      return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    }
    return DateTime.now().toUtc();
  }

  String _baseDateKey(Task task) {
    if (task.plannedStart != null && task.plannedStart!.isNotEmpty) {
      return task.plannedStart!.substring(0, 10);
    }
    if (task.plannedDate != null) return task.plannedDate!;
    if (task.dueDate != null) return task.dueDate!;
    return dateKey(DateTime.now());
  }
}

class TaskRepository extends _TaskRepositoryBase
    with
        _TaskListOps,
        _TaskCrudOps,
        _TaskCompletionOps,
        _TaskOccurrenceOps,
        _TaskQueryOps,
        _TaskMoveOps,
        _TaskTagOps,
        _TaskSmartListOps,
        _TaskTrashOps {
  TaskRepository(super._db);
}
