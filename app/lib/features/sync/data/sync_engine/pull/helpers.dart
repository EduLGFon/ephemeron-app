part of '../../sync_engine.dart';

extension on SyncEngine {
  Future<String?> _remoteCalendarId(String localId) async {
    final cal = await (_db.select(
      _db.calendars,
    )..where((c) => c.id.equals(localId))).getSingleOrNull();
    return cal?.remoteId;
  }

  Future<String?> _remoteTaskListId(String? localId) async {
    if (localId == null) return null;
    final list = await (_db.select(
      _db.taskLists,
    )..where((l) => l.id.equals(localId))).getSingleOrNull();
    return list?.remoteId;
  }

  Future<String?> _syncValue(String key) async {
    final row = await (_db.select(
      _db.syncState,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _setSyncValue(String key, String value) async {
    final now = _now();
    await _db
        .into(_db.syncState)
        .insertOnConflictUpdate(
          SyncStateCompanion.insert(
            key: key,
            value: Value(value),
            lastSyncAt: Value(now),
          ),
        );
  }

  Future<void> _setSyncMeta(String key, {String? error}) async {
    await _db
        .into(_db.syncState)
        .insertOnConflictUpdate(
          SyncStateCompanion.insert(
            key: '$key:meta',
            lastSyncAt: Value(_now()),
            lastError: Value(error),
          ),
        );
  }
}
