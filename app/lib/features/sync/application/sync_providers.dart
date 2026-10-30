// Sync providers: engine, status, manual triggers, auto-sync schedule.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/db/db_provider.dart';
import '../../../data/remote/backend_sync_api.dart';
import '../../../data/remote/google_api_client.dart';
import '../../auth/application/auth_providers.dart';
import '../../calendar/application/calendar_providers.dart';
import '../../settings/application/settings_providers.dart';
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
    debugPrint('[sync] notifier syncNow start');
    state = SyncStatus.syncing;
    final auth = ref.read(googleAuthProvider);
    final accounts = auth.accounts;
    if (accounts.isEmpty) {
      debugPrint('[sync] not signed in: offline');
      state = SyncStatus.offline;
      return;
    }
    SyncStatus last = SyncStatus.synced;
    for (final acct in accounts) {
      await auth.setActiveAccount(acct);
      final engine = SyncEngine(
        ref.read(appDatabaseProvider),
        clientFactory: () {
          try {
            return HttpGoogleApiClient(accessToken: () => auth.accessToken());
          } catch (_) {
            return null;
          }
        },
        account: acct,
      );
      debugPrint('[sync] signed in ($acct), calling engine');
      await engine.syncNow();
      last = engine.status;
    }
    state = last;
    if (last == SyncStatus.synced) {
      unawaited(ref.read(lastGoogleSyncAtProvider.notifier).recordNow());
      // Pulled events land in the events table; rebuild the visible
      // occurrence window so the calendar shows them right away.
      try {
        final window = ref.read(calendarStateProvider);
        final n = await ref
            .read(occurrenceRepositoryProvider)
            .rebuildWindow(
              windowStartUtc: window.fromUtc,
              windowEndUtc: window.toUtc,
            );
        debugPrint('[sync] occurrence cache rebuilt rows=$n');
        ref.invalidate(windowOccurrencesProvider(window));
      } catch (e) {
        debugPrint('[sync] occurrence cache rebuild failed: $e');
        // Cache rebuild is best-effort; next navigation rebuilds anyway.
      }
    }
  }
}

/// Last successful Google sync. Reactive cache of the persisted value in
/// SettingsRepository; drives title freshness colors.
final lastGoogleSyncAtProvider =
    NotifierProvider<LastGoogleSyncNotifier, DateTime?>(
      LastGoogleSyncNotifier.new,
    );

class LastGoogleSyncNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() {
    unawaited(_load());
    return null;
  }

  Future<void> _load() async {
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      state = repo.lastGoogleSyncAt;
    } catch (_) {
      // Prefs unavailable: stay null (titles render gray).
    }
  }

  Future<void> recordNow() async {
    state = DateTime.now().toUtc();
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      await repo.setLastGoogleSyncAt(state);
    } catch (_) {
      // Persistence is best-effort; in-memory state still drives the UI.
    }
  }
}

/// Battery-friendly auto-sync: one periodic timer, no background polling.
/// Manual syncs reschedule so the next auto run is a full interval later.
final googleAutoSyncServiceProvider = Provider<GoogleAutoSyncService>((ref) {
  final svc = GoogleAutoSyncService(ref);
  ref.onDispose(svc.dispose);
  return svc;
});

class GoogleAutoSyncService {
  GoogleAutoSyncService(this._ref);

  final Ref _ref;
  Timer? _timer;

  /// Starts (or restarts) the schedule from the persisted interval.
  Future<void> start() => reschedule();

  Future<void> reschedule() async {
    int intervalMin = AppConfig.syncIntervalMin;
    try {
      final repo = await _ref.read(settingsRepositoryProvider.future);
      intervalMin = repo.syncIntervalMin;
    } catch (_) {
      // Prefs unavailable: fall back to the compiled default.
    }
    _timer?.cancel();
    _timer = null;
    debugPrint('[sync] auto-sync reschedule intervalMin=$intervalMin');
    if (intervalMin <= 0) return;
    _timer = Timer.periodic(Duration(minutes: intervalMin), (_) => _tick());
  }

  Future<void> _tick() async {
    debugPrint('[sync] auto-sync tick');
    if (_ref.read(googleAuthProvider).accounts.isEmpty) {
      debugPrint('[sync] auto-sync tick skipped: signed out');
      return;
    }
    await _ref.read(syncStatusProvider.notifier).syncNow();
  }

  /// Manual sync (title tap): sync now, then restart the auto countdown.
  Future<void> syncNowAndReschedule() async {
    await _ref.read(syncStatusProvider.notifier).syncNow();
    await reschedule();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
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
