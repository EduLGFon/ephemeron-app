import 'package:permission_handler/permission_handler.dart';
import '../domain/alarm_preset.dart';

/// Requests the necessary system permissions for the given [AlarmPreset].
///
/// - [AlarmPreset.light] (notifications only) -> requests [Permission.notification].
/// - [AlarmPreset.medium], [AlarmPreset.strong], [AlarmPreset.constant]
///   (full-screen alarms) -> requests [Permission.notification],
///   [Permission.scheduleExactAlarm], and [Permission.systemAlertWindow].
Future<void> requestAlarmPermissions(AlarmPreset preset) async {
  try {
    if (preset == AlarmPreset.light) {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    } else {
      // For full screen / high priority alarms
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
      // Exact alarms are needed on Android 12+ to schedule exact notifications/alarms
      if (await Permission.scheduleExactAlarm.isDenied) {
        await Permission.scheduleExactAlarm.request();
      }
      // System alert window is needed to display full-screen alarms over other apps/lockscreen
      if (await Permission.systemAlertWindow.isDenied) {
        await Permission.systemAlertWindow.request();
      }
    }
  } catch (_) {
    // Gracefully handle environments/platforms where some permissions might not exist.
  }
}
