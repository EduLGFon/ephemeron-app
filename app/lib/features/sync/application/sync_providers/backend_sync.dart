part of '../sync_providers.dart';

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
