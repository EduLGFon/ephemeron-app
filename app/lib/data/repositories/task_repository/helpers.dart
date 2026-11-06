part of '../task_repository.dart';

extension TaskRepositoryHelpers on TaskRepository {
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
}
