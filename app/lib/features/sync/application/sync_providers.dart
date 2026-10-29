// Sync providers: engine, status, manual triggers.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/db/db_provider.dart';
import '../../../data/remote/backend_sync_api.dart';
import '../../../data/remote/google_api_client.dart';
import '../../auth/application/auth_providers.dart';
import '../data/backend_sync_engine.dart';
import '../data/sync_engine.dart';

final googleApiClientProvider = Provider<GoogleApiClient>((ref) {
  final auth = ref.watch(googleAuthProvider);
  return HttpGoogleApiClient(accessToken: auth.accessToken);
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SyncEngine(
    db,
    clientFactory: () {
      try {
        return ref.read(googleApiClientProvider);
      } catch (_) {
        return null;
      }
    },
  );
});

final syncStatusProvider = NotifierProvider<SyncStatusNotifier, SyncStatus>(
  SyncStatusNotifier.new,
);

class SyncStatusNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() => SyncStatus.synced;

  Future<void> syncNow() async {
    state = SyncStatus.syncing;
    final engine = ref.read(syncEngineProvider);
    final auth = ref.read(googleAuthProvider);
    if (!auth.isSignedIn) {
      state = SyncStatus.offline;
      return;
    }
    await engine.syncNow();
    state = engine.status;
  }
}

final failedChangesProvider = StreamProvider((ref) {
  return ref.watch(syncEngineProvider).watchFailed();
});

/// No backend URL configured (dev default): engine reports offline.
final backendSyncEngineProvider = Provider<BackendSyncEngine>((ref) {
  return BackendSyncEngine(
    ref.watch(appDatabaseProvider),
    ref.watch(backendAuthProvider),
    apiFactory: (_) {
      if (AppConfig.backendBaseUrl.isEmpty) return null;
      return HttpBackendSyncApi(
        accessToken: ref.read(backendAuthProvider).accessToken,
      );
    },
  );
});

final backendSyncStatusProvider =
    NotifierProvider<BackendSyncStatusNotifier, SyncStatus>(
      BackendSyncStatusNotifier.new,
    );

class BackendSyncStatusNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() => SyncStatus.synced;

  Future<void> syncNow() async {
    state = SyncStatus.syncing;
    final auth = ref.read(backendAuthProvider);
    if (!auth.isSignedIn) {
      state = SyncStatus.offline;
      return;
    }
    final engine = ref.read(backendSyncEngineProvider);
    await engine.syncNow();
    state = engine.status;
  }
}
