// Sync providers: engine, status, manual triggers, auto-sync schedule.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/db/db_provider.dart';
import '../../../data/remote/backend_sync_api.dart';
import '../../../data/remote/google_api_client.dart';
import '../../auth/application/auth_providers.dart';
import '../data/microsoft_sync_engine.dart';
import '../data/microsoft_graph_client.dart';
import '../../calendar/application/calendar_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../../settings/data/settings_repository.dart';
import '../../../core/power/power_saving_manager.dart';
import '../data/backend_sync_engine.dart';
import '../data/background_sync.dart';
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

/// Accounts whose last sync hit an auth/permission error (expired token,
/// revoked access, or a grant missing Calendar/Tasks scope). The account
/// screen shows a reconnect banner for these. Cleared per account after a
/// successful re-grant; re-added by the next failing sync.
final googleReconsentAccountsProvider =
    NotifierProvider<GoogleReconsentAccounts, List<String>>(
      GoogleReconsentAccounts.new,
    );

class GoogleReconsentAccounts extends Notifier<List<String>> {
  @override
  List<String> build() => const [];

  void set(List<String> accounts) => state = List.unmodifiable(accounts);

  void clear(String account) =>
      state = state.where((a) => a != account).toList();
}

final microsoftReconsentAccountsProvider =
    NotifierProvider<MicrosoftReconsentAccounts, List<String>>(
      MicrosoftReconsentAccounts.new,
    );

class MicrosoftReconsentAccounts extends Notifier<List<String>> {
  @override
  List<String> build() => const [];

  void set(List<String> accounts) => state = List.unmodifiable(accounts);

  void clear(String account) =>
      state = state.where((a) => a != account).toList();
}

class SyncStatusNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() => SyncStatus.synced;

  Future<void> syncNow() async {
    debugPrint('[sync] notifier syncNow start');
    state = SyncStatus.syncing;
    final googleAuth = ref.read(googleAuthProvider);
    final googleAccounts = googleAuth.accounts;
    final msAuth = ref.read(microsoftAuthProvider);
    await msAuth.restore();
    final msAccounts = msAuth.accounts;
    if (googleAccounts.isEmpty && msAccounts.isEmpty) {
      debugPrint('[sync] not signed in: offline');
      state = SyncStatus.offline;
      return;
    }
    bool allSucceeded = true;
    bool anyAttempted = false;
    bool anyPulled = false;
    // Google
    final needReconnectGoogle = <String>[];
    if (googleAccounts.isNotEmpty) {
      for (final acct in googleAccounts) {
        await googleAuth.setActiveAccount(acct);
        final engine = SyncEngine(
          ref.read(appDatabaseProvider),
          clientFactory: () {
            try {
              return HttpGoogleApiClient(
                accessToken: () => googleAuth.accessToken(),
              );
            } catch (_) {
              return null;
            }
          },
          account: acct,
        );
        debugPrint('[sync] signed in ($acct), calling engine');
        await engine.syncNow();
        if (engine.status != SyncStatus.synced) allSucceeded = false;
        if (engine.authFailure) needReconnectGoogle.add(acct);
        anyAttempted = true;
        if (engine.status == SyncStatus.synced) anyPulled = true;
      }
      ref
          .read(googleReconsentAccountsProvider.notifier)
          .set(needReconnectGoogle);
    }
    // Microsoft
    final needReconnectMs = <String>[];
    if (msAccounts.isNotEmpty) {
      for (final acct in msAccounts) {
        await msAuth.setActiveAccount(acct);
        final client = HttpMicrosoftGraphClient(
          accessToken: () => msAuth.accessTokenFor(acct),
        );
        final engine = MicrosoftSyncEngine(
          ref.read(appDatabaseProvider),
          client,
          acct,
        );
        final result = await engine.syncNow();
        if (result.authFailure) {
          needReconnectMs.add(acct);
          allSucceeded = false;
        }
        anyAttempted = true;
        anyPulled = true;
      }
      ref
          .read(microsoftReconsentAccountsProvider.notifier)
          .set(needReconnectMs);
    }
    if (!anyAttempted) {
      state = SyncStatus.offline;
      return;
    }
    final finalStatus = allSucceeded ? SyncStatus.synced : SyncStatus.error;
    state = finalStatus;
    if (finalStatus == SyncStatus.synced) {
      unawaited(ref.read(lastGoogleSyncAtProvider.notifier).recordNow());
    }
    if (anyPulled) {
      // Rebuild occurrence cache once after both loops.
      try {
        final range = ref.read(calendarCacheRangeProvider);
        final n = await ref
            .read(occurrenceRepositoryProvider)
            .rebuildWindow(
              windowStartUtc: range.fromUtc,
              windowEndUtc: range.toUtc,
            );
        debugPrint('[sync] occurrence cache rebuilt rows=$n');
        ref.invalidate(windowOccurrencesProvider(range));
      } catch (e) {
        debugPrint('[sync] occurrence cache rebuild failed: $e');
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
      final lowBattery = await PowerSavingManager.instance.isLowBattery;
      final savePower =
          repo.powerSavingMode == PowerSavingMode.on ||
          (repo.powerSavingMode == PowerSavingMode.auto && lowBattery);
      // Battery-aware: halve frequency when power saving is active.
      if (savePower && intervalMin > 0) {
        intervalMin = intervalMin * 2;
      }
    } catch (_) {
      // Prefs unavailable: fall back to the compiled default.
    }
    _timer?.cancel();
    _timer = null;
    debugPrint('[sync] auto-sync reschedule intervalMin=$intervalMin');
    // Keep a WorkManager periodic task in step with the foreground timer so
    // sync also runs when the app was killed. 0 cancels the background task.
    unawaited(BackgroundSync.reschedule(intervalMin));
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

/// Battery-friendly backend auto-sync: mirrors GoogleAutoSyncService.
/// Manual syncs reschedule so the next auto run is a full interval later.
final backendAutoSyncServiceProvider = Provider<BackendAutoSyncService>((ref) {
  final svc = BackendAutoSyncService(ref);
  ref.onDispose(svc.dispose);
  return svc;
});

class BackendAutoSyncService {
  BackendAutoSyncService(this._ref);

  final Ref _ref;
  Timer? _timer;

  Future<void> start() => reschedule();

  Future<void> reschedule() async {
    int intervalMin = 0;
    try {
      final repo = await _ref.read(settingsRepositoryProvider.future);
      intervalMin = repo.backendSyncIntervalMin;
      final lowBattery = await PowerSavingManager.instance.isLowBattery;
      final savePower =
          repo.powerSavingMode == PowerSavingMode.on ||
          (repo.powerSavingMode == PowerSavingMode.auto && lowBattery);
      if (savePower && intervalMin > 0) {
        intervalMin = intervalMin * 2;
      }
    } catch (_) {
      // Prefs unavailable: stay manual.
    }
    _timer?.cancel();
    _timer = null;
    unawaited(BackgroundSync.reschedule(intervalMin));
    if (intervalMin <= 0) return;
    _timer = Timer.periodic(Duration(minutes: intervalMin), (_) => _tick());
  }

  Future<void> _tick() async {
    if (!_ref.read(backendAuthProvider).isSignedIn) return;
    await _ref.read(backendSyncStatusProvider.notifier).syncNow();
  }

  Future<void> syncNowAndReschedule() async {
    await _ref.read(backendSyncStatusProvider.notifier).syncNow();
    await reschedule();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
