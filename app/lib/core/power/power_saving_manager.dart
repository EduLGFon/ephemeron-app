// Battery-aware helper. Used to halve sync frequency when the device is
// low on battery and not charging, honouring PowerSavingMode.auto.
import 'package:battery_plus/battery_plus.dart';

class PowerSavingManager {
  PowerSavingManager._();
  static final PowerSavingManager instance = PowerSavingManager._();

  final Battery _battery = Battery();

  Future<bool> get isLowBattery async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      if (state == BatteryState.charging || state == BatteryState.full) {
        return false;
      }
      return level < 15;
    } catch (_) {
      return false;
    }
  }
}