import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local/database.dart';
import '../../alarms/data/alarm_scheduler.dart';
import '../../alarms/domain/alarm_preset.dart';
import '../../alarms/domain/reminder_offset.dart';
// ignore: unused_import
import '../../matrix/domain/matrix_quadrant.dart';
// ignore: unused_import
import '../domain/smart_list_type.dart';
import '../domain/task_recurrence.dart';
import '../domain/task_sort_option.dart';

const _uuid = Uuid();

class TaskRepository {
  TaskRepository(this._db, this._alarmScheduler, this._googleTasksMirror);

  final AppDatabase _db;
  // ignore: unused_field
  final AlarmScheduler _alarmScheduler;
  // ignore: unused_field
  final Object? _googleTasksMirror;

  Stream<List<TaskList>> watchLists() {
    return (_db.select(_db.lists)
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .watch();
  }

  Future<TaskList> createList({
    required String name,
    String colorHex = '#1B4B4A',
  }) async {
    final id = _uuid.v4();
    await _db.into(_db.lists).insert(
          ListsCompanion.insert(
            id: Value(id),
            name: name,
            colorHex: Value(colorHex),
          ),
        );
    return (_db.select(_db.lists)..where((t) => t.id.equals(id))).getSingle();
  }

  // ignore: unused_element
  Future<TaskList> _inboxList() {
    return (_db.select(_db.lists)..where((t) => t.isInbox.equals(true)))
        .getSingle();
  }

  Stream<List<Task>> watchTasksInList(
    String listId, {
    bool? isCompleted,
    TaskSortOption? sortOption,
  }) {
    final query = _db.select(_db.tasks)
      ..where((t) =>
          t.listId.equals(listId) &
          t.isDeleted.equals(false) &
          t.parentTaskId.isNull());

    if (isCompleted != null) {
      query.where((t) => t.isCompleted.equals(isCompleted));
    }
    query.orderBy([(t) => OrderingTerm.asc(t.sortOrder)]);
    return query.watch();
  }

  Stream<List<Task>> watchSubtasks(String parentTaskId) {
    return (_db.select(_db.tasks)
          ..where((t) =>
              t.parentTaskId.equals(parentTaskId) & t.isDeleted.equals(false)))
        .watch();
  }

  Future<Task> createTask({
    required String listId,
    required String title,
    String? description,
    int priority = 0,
    DateTime? dueDate,
    bool dueHasTime = false,
    TaskRecurrence recurrence = TaskRecurrence.none,
    int durationMinutes = 30,
    bool isWontDo = false,
    String? parentTaskId,
    AlarmPreset? alarmPreset,
    List<ReminderOffset> reminderOffsets = const [],
  }) async {
    final id = _uuid.v4();

    await _db.into(_db.tasks).insert(
          TasksCompanion.insert(
            id: Value(id),
            listId: listId,
            parentTaskId: Value(parentTaskId),
            title: title,
            description: Value(description),
            priority: Value(priority),
            dueDate: Value(dueDate),
            dueHasTime: Value(dueHasTime),
            recurrenceRule: Value(
              recurrence.isRecurring ? recurrence.encode() : null,
            ),
            durationMinutes: Value(durationMinutes),
            isWontDo: Value(isWontDo),
            alarmPreset: Value(alarmPreset?.name),
            reminderOffsetsMinutes: Value(_encodeOffsets(reminderOffsets)),
          ),
        );

    return (_db.select(_db.tasks)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> updateTask(
    String taskId, {
    String? title,
    String? description,
    int? priority,
    Value<DateTime?>? dueDate,
    bool? dueHasTime,
    TaskRecurrence? recurrence,
    int? durationMinutes,
    bool? isWontDo,
    Value<AlarmPreset?>? alarmPreset,
    List<ReminderOffset>? reminderOffsets,
  }) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
        title: title != null ? Value(title) : const Value.absent(),
        description:
            description != null ? Value(description) : const Value.absent(),
        priority: priority != null ? Value(priority) : const Value.absent(),
        dueDate: dueDate ?? const Value.absent(),
        dueHasTime:
            dueHasTime != null ? Value(dueHasTime) : const Value.absent(),
        recurrenceRule: recurrence != null
            ? Value(recurrence.isRecurring ? recurrence.encode() : null)
            : const Value.absent(),
        durationMinutes: durationMinutes != null
            ? Value(durationMinutes)
            : const Value.absent(),
        isWontDo: isWontDo != null ? Value(isWontDo) : const Value.absent(),
        alarmPreset: alarmPreset != null
            ? Value(alarmPreset.value?.name)
            : const Value.absent(),
        reminderOffsetsMinutes: reminderOffsets != null
            ? Value(_encodeOffsets(reminderOffsets))
            : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> toggleWontDo(String taskId) async {
    final task = await _getTask(taskId);
    if (task == null) return;
    await (_db.update(_db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(isWontDo: Value(!task.isWontDo)),
    );
  }

  Future<Task?> _getTask(String taskId) {
    return (_db.select(_db.tasks)..where((t) => t.id.equals(taskId)))
        .getSingleOrNull();
  }

  Future<CustomSmartList> createCustomSmartList({
    required String name,
    String colorHex = '#1B4B4A',
    int? minPriority,
    String? dateFilter,
    String? tagId,
    bool? isCompletedFilter,
  }) async {
    final id = _uuid.v4();
    await _db.into(_db.customSmartLists).insert(
          CustomSmartListsCompanion.insert(
            id: Value(id),
            name: name,
            colorHex: Value(colorHex),
            minPriority: Value(minPriority),
            dateFilter: Value(dateFilter),
            tagId: Value(tagId),
            isCompletedFilter: Value(isCompletedFilter),
          ),
        );
    return (_db.select(_db.customSmartLists)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  Stream<List<Task>> watchTasksForCustomSmartList(CustomSmartList smartList) {
    SimpleSelectStatement<$TasksTable, Task> selectStatement =
        _db.select(_db.tasks);
    JoinedSelectStatement selectWithJoin;

    if (smartList.tagId != null) {
      selectWithJoin = selectStatement.join([
        innerJoin(_db.taskTags, _db.taskTags.taskId.equalsExp(_db.tasks.id)),
      ]);
      selectWithJoin.where(_db.taskTags.tagId.equals(smartList.tagId!));
    } else {
      selectWithJoin = selectStatement.join([]);
    }

    selectWithJoin.where(_db.tasks.parentTaskId.isNull());
    selectWithJoin.where(_db.tasks.isDeleted.equals(false));
    selectWithJoin.where(_db.tasks.isWontDo.equals(false));

    if (smartList.isCompletedFilter != null) {
      selectWithJoin
          .where(_db.tasks.isCompleted.equals(smartList.isCompletedFilter!));
    }

    if (smartList.minPriority != null) {
      selectWithJoin.where(
          _db.tasks.priority.isBiggerOrEqualValue(smartList.minPriority!));
    }

    if (smartList.dateFilter != null) {
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      if (smartList.dateFilter == 'today') {
        final startOfTomorrow = startOfToday.add(const Duration(days: 1));
        selectWithJoin
            .where(_db.tasks.dueDate.isSmallerThanValue(startOfTomorrow));
      } else if (smartList.dateFilter == 'tomorrow') {
        final startOfTomorrow = startOfToday.add(const Duration(days: 1));
        final startOfDayAfterTomorrow =
            startOfToday.add(const Duration(days: 2));
        selectWithJoin.where(
            _db.tasks.dueDate.isBiggerOrEqualValue(startOfTomorrow) &
                _db.tasks.dueDate.isSmallerThanValue(startOfDayAfterTomorrow));
      } else if (smartList.dateFilter == 'thisWeek') {
        final weekday = now.weekday;
        final startOfWeek = startOfToday.subtract(Duration(days: weekday - 1));
        final endOfWeek = startOfWeek.add(const Duration(days: 7));
        selectWithJoin.where(_db.tasks.dueDate.isSmallerThanValue(endOfWeek));
      } else if (smartList.dateFilter == 'next7Days') {
        final startOfNext7 = startOfToday.add(const Duration(days: 7));
        selectWithJoin
            .where(_db.tasks.dueDate.isSmallerThanValue(startOfNext7));
      }
    }

    selectWithJoin.orderBy([OrderingTerm.asc(_db.tasks.dueDate)]);
    return selectWithJoin
        .watch()
        .map((rows) => rows.map((r) => r.readTable(_db.tasks)).toList());
  }

  String? _encodeOffsets(List<ReminderOffset> offsets) {
    if (offsets.isEmpty) return null;
    return jsonEncode(offsets.map((o) => o.beforeDue.inMinutes).toList());
  }
}

class TaskCalendarEntry {
  final Task task;
  final String? tagColorHex;
  TaskCalendarEntry(this.task, this.tagColorHex);
}

extension TaskCalendarRepositoryExtension on TaskRepository {
  Stream<List<TaskCalendarEntry>> watchTasksForCalendar() {
    final query = _db.select(_db.tasks).join([
      leftOuterJoin(_db.taskTags, _db.taskTags.taskId.equalsExp(_db.tasks.id)),
      leftOuterJoin(_db.tags, _db.tags.id.equalsExp(_db.taskTags.tagId)),
    ])
      ..where(_db.tasks.isDeleted.equals(false) &
          _db.tasks.isWontDo.equals(false) &
          _db.tasks.dueDate.isNotNull());

    return query.watch().map((rows) {
      final list = <TaskCalendarEntry>[];
      for (final row in rows) {
        final task = row.readTable(_db.tasks);
        final tag = row.readTableOrNull(_db.tags);
        list.add(TaskCalendarEntry(task, tag?.colorHex));
      }
      return list;
    });
  }
}