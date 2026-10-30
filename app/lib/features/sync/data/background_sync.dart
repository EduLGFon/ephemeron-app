// Periodic background sync via WorkManager (PLAN 6.1).
// Foreground auto-sync stops when the OS kills the app; this registers a
// constrained periodic task (network connected, battery not low) that runs
// headless: it reopens the Drift database, restores stored credentials from
// the keystore, and runs the Google + backend engines best-effort.
// Google data still never touches the backend: the two engines share only
// the local database handle.
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/config/app_config.dart';
import '../../../data/drift/app_database.dart';
import '../../../data/remote/backend_sync_api.dart';
import '../../../data/remote/google_api_client.dart';
import '../../auth/data/backend_auth.dart';
import '../../auth/data/google_auth.dart';
import '../data/backend_sync_engine.dart';
import '../data/sync_engine.dart';

const _taskName = 'ephemeron-periodic-sync';

@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != _taskName) return true;
    try {
      final db = AppDatabase();
      try {
        final googleAuth = GoogleAuth();
        await googleAuth.restore();
        for (final account in googleAuth.accounts) {
          await googleAuth.setActiveAccount(account);
          final engine = SyncEngine(
            db,
            clientFactory: () {
              try {
                return HttpGoogleApiClient(
                  accessToken: () => googleAuth.accessToken(),
                );
              } catch (_) {
                return null;
              }
            },
            account: account,
          );
          await engine.syncNow();
        }
        final backendAuth = BackendAuth();
        await backendAuth.restore();
        if (backendAuth.isSignedIn && AppConfig.backendBaseUrl.isNotEmpty) {
          final backend = BackendSyncEngine(
            db,
            backendAuth,
            apiFactory: (token) => HttpBackendSyncApi(accessToken: token),
          );
          await backend.syncNow();
        }
      } finally {
        await db.close();
      }
      return true;
    } catch (e) {
      debugPrint('[bg-sync] failed: $e');
      // Retry with backoff rather than dropping the schedule.
      return false;
    }
  });
}

class BackgroundSync {
  /// Registers or replaces the periodic task. intervalMin is clamped to the
  /// WorkManager 15-minute minimum; 0 cancels the task. Android and iOS
  /// only; other platforms are no-ops.
  static Future<void> reschedule(int intervalMin) async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    try {
      await Workmanager().initialize(
        backgroundSyncDispatcher,
        isInDebugMode: false,
      );
      if (intervalMin <= 0) {
        await Workmanager().cancelByUniqueName(_taskName);
        return;
      }
      final minutes = intervalMin < 15 ? 15 : intervalMin;
      await Workmanager().registerPeriodicTask(
        _taskName,
        _taskName,
        frequency: Duration(minutes: minutes),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      );
    } catch (e) {
      debugPrint('[bg-sync] schedule failed: $e');
    }
  }
}
