part of '../sync_providers.dart';

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
