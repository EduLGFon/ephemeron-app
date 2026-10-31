// AlarmScheduler is the ONLY place that schedules OS alarms/notifications.
// Native code does the ringing; Dart only registers and mirrors state.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/logger/logger.dart';

final _log = AppLogger();

class AlarmScheduler {
  static const _channel = MethodChannel('ephemeron/alarms');

  static Future<bool> get isSupported async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final v = await _channel.invokeMethod<bool>('ping');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> schedule({
    required int requestCode,
    required int fireAtUtcMs,
    required bool useAlarmClock,
    required String title,
    String preset = 'medium',
    String? sourceType,
    String? sourceId,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      _log.debug('alarm schedule stubbed on $defaultTargetPlatform');
      return;
    }
    await _channel.invokeMethod<void>('schedule', {
      'requestCode': requestCode,
      'fireAtUtcMs': fireAtUtcMs,
      'useAlarmClock': useAlarmClock,
      'title': title,
      'preset': preset,
      'sourceType': sourceType,
      'sourceId': sourceId,
    });
  }

  static Future<void> cancel(int requestCode) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('cancel', {'requestCode': requestCode});
  }

  static Future<void> cancelAll() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('cancelAll');
  }

  /// Test button: rings in 10 seconds.
  static Future<void> testAlarm() async {
    await schedule(
      requestCode: 1,
      fireAtUtcMs: DateTime.now().toUtc().millisecondsSinceEpoch + 10000,
      useAlarmClock: false,
      title: 'Test alarm',
      sourceType: 'test',
      sourceId: 'test',
    );
  }

  static Future<bool> canScheduleExact() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final v = await _channel.invokeMethod<bool>('canScheduleExact');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openExactAlarmSettings() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('openExactAlarmSettings');
  }

  static Future<void> openBatterySettings() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('openBatterySettings');
  }
}
