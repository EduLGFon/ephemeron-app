// Sync providers: engine, status, manual triggers.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/db_provider.dart';
import '../../../data/remote/google_api_client.dart';
import '../../auth/application/auth_providers.dart';
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
