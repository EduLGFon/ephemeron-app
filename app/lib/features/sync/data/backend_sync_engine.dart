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

part 'backend_sync_engine/push.dart';
part 'backend_sync_engine/pull.dart';
part 'backend_sync_engine/merge.dart';

abstract class _BackendSyncEngineBase {
  _BackendSyncEngineBase(
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

  Future<void> _push(BackendSyncApi api);
  Future<void> _pull(BackendSyncApi api);
  Future<void> _mergeHabit(Map<String, dynamic> m);
  Future<void> _mergeLog(Map<String, dynamic> m);
  Future<void> _mergeFocus(Map<String, dynamic> m);

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

class BackendSyncEngine extends _BackendSyncEngineBase
    with _BackendSyncPushOps, _BackendSyncPullOps, _BackendSyncMergeOps {
  BackendSyncEngine(super._db, super._auth, {super.apiFactory});
}
