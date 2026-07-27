import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:battery_plus/battery_plus.dart';

import 'app_settings_provider.dart';

/// Notifies when battery is low (< 15%) and power saving is on auto
class LowBatteryWarningNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  @override
  set state(bool value) => super.state = value;
}

final lowBatteryWarningProvider = NotifierProvider<LowBatteryWarningNotifier, bool>(() => LowBatteryWarningNotifier());

/// Listens to app lifecycle changes and refreshes the battery save mode state
/// automatically when the app comes back to the foreground.
class PowerSavingManager extends WidgetsBindingObserver {
  PowerSavingManager(this.ref) {
    WidgetsBinding.instance.addObserver(this);
    // Initial check
    _checkBattery();
  }

  final Ref ref;
  final Battery _battery = Battery();
  bool _lowBatterySuggestionShown = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkBattery();
    }
  }

  Future<void> _checkBattery() async {
    final notifier = ref.read(appSettingsProvider.notifier);
    await notifier.refreshBatteryState();
    
    try {
      final level = await _battery.batteryLevel;
      final settings = ref.read(appSettingsProvider);
      
      if (level < 15 && settings.powerSavingMode == PowerSavingMode.auto && !_lowBatterySuggestionShown) {
        ref.read(lowBatteryWarningProvider.notifier).state = true;
        _lowBatterySuggestionShown = true;
      }
    } catch (_) {
      // Ignored if battery check fails
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}

final powerSavingManagerProvider = Provider<PowerSavingManager>((ref) {
  final manager = PowerSavingManager(ref);
  ref.onDispose(manager.dispose);
  return manager;
});
