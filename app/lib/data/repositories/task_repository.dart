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
import 'package:ephemeron/domain/tasks/recurring_task.dart';

class TaskRepository {
  TaskRepository(this._db);

  final AppDatabase _db;

  Future<void> _enqueue(String entity, String entityId, String op) =>
      enqueueOutbox(_db, entity: entity, entityId: entityId, op: op);

  // Lists.

  Future<String> createList(String name, {String? color}) async {
    final id = newId();
    final now = nowMs();
    await _db
        .into(_db.taskLists)
        .insert(
          TaskListsCompanion.insert(
            id: id,
            name: name,
            color: Value(color),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _enqueue('task_list', id, 'create');
    return id;
  }

  Stream<List<TaskList>> watchLists() {
    return (_db.select(
      _db.taskLists,
    )..orderBy([(l) => OrderingTerm.asc(l.sortOrder)])).watch();
  }

  Future<void> deleteList(String id) async {
    await _db.transaction(() async {
      await (_db.update(_db.tasks)..where((t) => t.listId.equals(id))).write(
        const TasksCompanion(listId: Value(null)),
      );
      await (_db.delete(_db.taskLists)..where((l) => l.id.equals(id))).go();
    });
    await _enqueue('task_list', id, 'delete');
  }

  // Tasks.

  Future<String> createTask({
    required String title,
    String? listId,
    String? notes,
    int priority = 0,
    String? dueDate,
    int? dueTime,
    int? durationMin,
    String? rrule,
    String? repeatMode,
    String? parentId,
    bool pinned = false,
    List<String> tags = const [],
    String? alarmPreset,
  }) async {
    final id = newId();
    final now = nowMs();
    var list = listId;
    list ??= await _defaultListId();
    await _db
        .into(_db.tasks)
        .insert(
          TasksCompanion.insert(
            id: id,
            title: Value(title),
            listId: Value(list),
            notes: Value(notes),
            priority: Value(priority),
            dueDate: Value(dueDate),
            dueTime: Value(dueTime),
            durationMin: Value(durationMin),
            rrule: Value(rrule),
            repeatMode: Value(repeatMode ?? 'from_due_date'),
            parentId: Value(parentId),
            pinned: Value(pinned),
            alarmPreset: Value(alarmPreset),
            createdAt: now,
            updatedAt: now,
          ),
        );
    if (tags.isNotEmpty) await setTaskTags(id, tags);
    await _enqueue('task', id, 'create');
    return id;
  }

  Future<String?> _defaultListId() async {
    final lists =
        await (_db.select(_db.taskLists)
              ..orderBy([(l) => OrderingTerm.asc(l.sortOrder)])
              ..limit(1))
            .get();
    return lists.isEmpty ? null : lists.single.id;
  }

  Stream<List<Task>> watchOpen({String? listId}) {
    final q = _db.select(_db.tasks)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            t.completedAt.isNull() &
            (listId == null
                ? t.parentId.isNull()
                : t.listId.equals(listId) & t.parentId.isNull()),
      );
    q.orderBy([
      (t) => OrderingTerm.desc(t.pinned),
      (t) => OrderingTerm.asc(t.dueDate),
      (t) => OrderingTerm.asc(t.sortOrder),
    ]);
    return q.watch();
  }

  Stream<List<Task>> watchTrash() {
    return (_db.select(_db.tasks)
          ..where((t) => t.deletedAt.isNotNull())
          ..orderBy([(t) => OrderingTerm.desc(t.deletedAt)]))
        .watch();
  }

  String _like(String query) => '%${sanitizeSearch(query)}%';

  bool _blank(String query) => sanitizeSearch(query).trim().isEmpty;

  /// Global-search hits: open and completed tasks, newest first.
  Future<List<Task>> searchTasks(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty || _blank(q)) return [];
    final like = _like(q);
    return (_db.select(_db.tasks)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                (t.title.like(like) | t.notes.like(like)),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
          ..limit(limit))
        .get();
  }

  Future<List<Tag>> searchTags(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty || _blank(q)) return [];
    return (_db.select(_db.tags)
          ..where((t) => t.name.like(_like(q)))
          ..orderBy([(t) => OrderingTerm.asc(t.name)])
          ..limit(limit))
        .get();
  }

  Stream<List<Task>> watchCompleted({String? listId, int limit = 200}) {
    final q = _db.select(_db.tasks)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            t.completedAt.isNotNull() &
            (listId == null ? const Constant(true) : t.listId.equals(listId)),
      );
    q
      ..orderBy([(t) => OrderingTerm.desc(t.completedAt)])
      ..limit(limit);
    return q.watch();
  }

  Stream<List<Task>> watchSubtasks(String parentId) {
    return (_db.select(_db.tasks)
          ..where((t) => t.parentId.equals(parentId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .watch();
  }

  /// Returns [done, total] for subtasks.
  Future<List<int>> subtaskProgress(String parentId) async {
    final subs = await (_db.select(
      _db.tasks,
    )..where((t) => t.parentId.equals(parentId) & t.deletedAt.isNull())).get();
    return [subs.where((s) => s.completedAt != null).length, subs.length];
  }

  Future<void> updateTask(
    String id, {
    String? title,
    String? notes,
    int? priority,
    String? Function()? dueDate,
    int? Function()? dueTime,
    int? Function()? durationMin,
    String? Function()? rrule,
    String? listId,
    bool? pinned,
    bool? wontDo,
    int? sortOrder,
    String? Function()? alarmPreset,
  }) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        title: title == null ? const Value.absent() : Value(title),
        notes: notes == null ? const Value.absent() : Value(notes),
        priority: priority == null ? const Value.absent() : Value(priority),
        dueDate: dueDate == null ? const Value.absent() : Value(dueDate()),
        dueTime: dueTime == null ? const Value.absent() : Value(dueTime()),
        durationMin: durationMin == null
            ? const Value.absent()
            : Value(durationMin()),
        rrule: rrule == null ? const Value.absent() : Value(rrule()),
        listId: listId == null ? const Value.absent() : Value(listId),
        pinned: pinned == null ? const Value.absent() : Value(pinned),
        wontDo: wontDo == null ? const Value.absent() : Value(wontDo),
        sortOrder: sortOrder == null ? const Value.absent() : Value(sortOrder),
        alarmPreset: alarmPreset == null
            ? const Value.absent()
            : Value(alarmPreset()),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
    await _enqueue('task', id, 'update');
  }

  Future<void> completeTask(String id, {DateTime? at}) async {
    final task = await (_db.select(
      _db.tasks,
    )..where((t) => t.id.equals(id))).getSingle();
    final completedMs = (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
          completedAt: Value(completedMs),
          updatedAt: Value(nowMs()),
          dirty: const Value(true),
        ),
      );
      if (task.rrule != null && task.rrule!.isNotEmpty) {
        final next = nextTaskDueDate(
          currentDueUtc: _taskDueUtc(task),
          completedAtUtc: DateTime.fromMillisecondsSinceEpoch(
            completedMs,
            isUtc: true,
          ),
          rrule: task.rrule,
          mode: task.repeatMode ?? 'from_due_date',
        );
        if (next != null) {
          final tagIds = await taskTagIds(id);
          final tagNames = <String>[];
          for (final tid in tagIds) {
            final tag = await (_db.select(
              _db.tags,
            )..where((g) => g.id.equals(tid))).getSingleOrNull();
            if (tag != null) tagNames.add(tag.name);
          }
          await createTask(
            title: task.title,
            listId: task.listId,
            notes: task.notes,
            priority: task.priority,
            dueDate: dateKey(next),
            dueTime: (next.hour == 0 && next.minute == 0)
                ? null
                : next.hour * 60 + next.minute,
            durationMin: task.durationMin,
            rrule: task.rrule,
            repeatMode: task.repeatMode,
            parentId: task.parentId,
            tags: tagNames,
          );
        }
      }
    });
    await _enqueue('task', id, 'update');
  }

  Future<void> uncompleteTask(String id) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        completedAt: const Value(null),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
    await _enqueue('task', id, 'update');
  }

  /// Advances a recurring task to its next due date without completing.
  Future<void> skipOccurrence(String id) async {
    final task = await (_db.select(
      _db.tasks,
    )..where((t) => t.id.equals(id))).getSingle();
    if (task.rrule == null || task.rrule!.isEmpty) return;
    final base = _taskDueUtc(task) ?? DateTime.now().toUtc();
    final next = nextTaskDueDate(
      currentDueUtc: base,
      completedAtUtc: base,
      rrule: task.rrule,
      mode: 'from_due_date',
    );
    if (next == null) return;
    await updateTask(
      id,
      dueDate: () => dateKey(next),
      dueTime: () => (next.hour == 0 && next.minute == 0)
          ? null
          : next.hour * 60 + next.minute,
    );
  }

  DateTime? _taskDueUtc(Task task) {
    if (task.dueDate == null) return null;
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

  /// Soft-deletes; returns ids for undo snackbars.
  Future<List<String>> softDeleteTasks(List<String> ids) async {
    final now = nowMs();
    await (_db.update(_db.tasks)..where((t) => t.id.isIn(ids))).write(
      TasksCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
    for (final id in ids) {
      await _enqueue('task', id, 'delete');
    }
    return ids;
  }

  Future<void> restoreTasks(List<String> ids) async {
    await (_db.update(_db.tasks)..where((t) => t.id.isIn(ids))).write(
      TasksCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
    for (final id in ids) {
      await _enqueue('task', id, 'update');
    }
  }

  /// Moves tasks; returns previous list ids for undo.
  Future<Map<String, String?>> moveTasks(
    List<String> ids,
    String? listId,
  ) async {
    final prev = <String, String?>{};
    await _db.transaction(() async {
      for (final id in ids) {
        final task = await (_db.select(
          _db.tasks,
        )..where((t) => t.id.equals(id))).getSingle();
        prev[id] = task.listId;
        await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
          TasksCompanion(
            listId: Value(listId),
            updatedAt: Value(nowMs()),
            dirty: const Value(true),
          ),
        );
      }
    });
    for (final id in ids) {
      await _enqueue('task', id, 'update');
    }
    return prev;
  }

  /// Permanent delete of one trashed task.
  Future<void> purgeTask(String id) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.taskTags,
      )..where((tt) => tt.taskId.equals(id))).go();
      await (_db.delete(_db.tasks)..where((t) => t.id.equals(id))).go();
    });
  }

  /// Purges items deleted more than [olderThanDays] ago (default 30).
  Future<int> emptyTrash({int olderThanDays = 30}) async {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: olderThanDays))
        .millisecondsSinceEpoch;
    final old =
        await (_db.select(_db.tasks)..where(
              (t) =>
                  t.deletedAt.isNotNull() &
                  t.deletedAt.isSmallerThanValue(cutoff),
            ))
            .get();
    for (final t in old) {
      await purgeTask(t.id);
    }
    return old.length;
  }

  // Tags.

  Future<String> ensureTag(String name, {String? color}) async {
    final clean = name.trim().toLowerCase();
    final existing = await (_db.select(
      _db.tags,
    )..where((g) => g.name.equals(clean))).getSingleOrNull();
    if (existing != null) return existing.id;
    final id = newId();
    final now = nowMs();
    await _db
        .into(_db.tags)
        .insert(
          TagsCompanion.insert(
            id: id,
            name: clean,
            color: Value(color),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Stream<List<Tag>> watchTags() {
    return (_db.select(
      _db.tags,
    )..orderBy([(g) => OrderingTerm.asc(g.name)])).watch();
  }

  Future<List<String>> taskTagIds(String taskId) async {
    final rows = await (_db.select(
      _db.taskTags,
    )..where((tt) => tt.taskId.equals(taskId))).get();
    return rows.map((r) => r.tagId).toList();
  }

  Future<void> setTaskTags(String taskId, List<String> names) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.taskTags,
      )..where((tt) => tt.taskId.equals(taskId))).go();
      for (final n in names) {
        final tagId = await ensureTag(n);
        await _db
            .into(_db.taskTags)
            .insert(TaskTagsCompanion.insert(taskId: taskId, tagId: tagId));
      }
      await (_db.update(_db.tasks)..where((t) => t.id.equals(taskId))).write(
        TasksCompanion(updatedAt: Value(nowMs())),
      );
    });
    await _enqueue('task', taskId, 'update');
  }

  // Smart lists.

  Future<String> createSmartList(
    String name,
    Map<String, Object?> filter,
  ) async {
    final id = newId();
    final now = nowMs();
    await _db
        .into(_db.smartLists)
        .insert(
          SmartListsCompanion.insert(
            id: id,
            name: name,
            filterJson: Value(jsonEncode(filter)),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Stream<List<SmartList>> watchSmartLists() {
    return (_db.select(
      _db.smartLists,
    )..orderBy([(s) => OrderingTerm.asc(s.name)])).watch();
  }

  /// Evaluates a filter: listIds, tagIds, priorities, dueFrom/dueTo
  /// (YYYY-MM-DD), showCompleted, query.
  Future<List<Task>> evalSmartList(Map<String, Object?> filter) async {
    final showCompleted = filter['showCompleted'] == true;
    final q = _db.select(_db.tasks)..where((t) => t.deletedAt.isNull());
    if (!showCompleted) {
      q.where((t) => t.completedAt.isNull());
    }
    final listIds = (filter['listIds'] as List?)?.cast<String>() ?? const [];
    if (listIds.isNotEmpty) {
      q.where((t) => t.listId.isIn(listIds));
    }
    final pris = (filter['priorities'] as List?)?.cast<int>() ?? const [];
    if (pris.isNotEmpty) {
      q.where((t) => t.priority.isIn(pris));
    }
    final dueFrom = filter['dueFrom'] as String?;
    if (dueFrom != null) {
      q.where((t) => t.dueDate.isBiggerOrEqualValue(dueFrom));
    }
    final dueTo = filter['dueTo'] as String?;
    if (dueTo != null) {
      q.where((t) => t.dueDate.isSmallerOrEqualValue(dueTo));
    }
    final tagIds = (filter['tagIds'] as List?)?.cast<String>() ?? const [];
    if (tagIds.isNotEmpty) {
      final tagged = await (_db.select(
        _db.taskTags,
      )..where((tt) => tt.tagId.isIn(tagIds))).get();
      final taskIds = tagged.map((r) => r.taskId).toSet().toList();
      if (taskIds.isEmpty) return [];
      q.where((t) => t.id.isIn(taskIds));
    }
    final query = (filter['query'] as String?)?.trim().toLowerCase();
    if (query != null && query.isNotEmpty) {
      q.where((t) => t.title.like('%$query%') | t.notes.like('%$query%'));
    }
    q.orderBy([
      (t) => OrderingTerm.desc(t.pinned),
      (t) => OrderingTerm.asc(t.dueDate),
      (t) => OrderingTerm.asc(t.sortOrder),
    ]);
    return q.get();
  }
}
