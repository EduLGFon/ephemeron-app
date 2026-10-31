// System launcher: opens URLs, DND access, focus chronometer.
// Android-only methods go through the ephemeron/system channel registered
// in MainActivity. Other platforms return false (callers fall back).
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SystemLauncher {
  static const _channel = MethodChannel('ephemeron/system');

  /// Opens [url] in the system browser. False on unsupported platforms.
  static Future<bool> openUrl(String url) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('openUrl', {'url': url});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> get hasDndAccess async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('hasDndAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openDndSettings() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('openDndSettings');
    } catch (_) {}
  }

  /// Requests alarms-only DND. Returns false when access is not granted.
  static Future<bool> setDnd(bool enabled) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('setDnd', {
            'enabled': enabled,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Shows an OS-rendered chronometer notification while focus runs.
  /// No per-second Dart wakeups; the OS renders the ticking clock.
  static Future<void> startFocusChronometer(
    String title,
    int startUtcMs,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('startFocusChronometer', {
        'title': title,
        'startUtcMs': startUtcMs,
      });
    } catch (_) {}
  }

  static Future<void> stopFocusChronometer() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('stopFocusChronometer');
    } catch (_) {}
  }

  /// Text shared into the app (Android SEND intent). Consumed once.
  static Future<String?> consumeSharedText() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await _channel.invokeMethod<String>('getSharedText');
    } catch (_) {
      return null;
    }
  }

  /// Launcher-shortcut action (new_task/new_event/start_focus). Once.
  static Future<String?> consumeLaunchAction() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await _channel.invokeMethod<String>('getLaunchAction');
    } catch (_) {
      return null;
    }
  }
}
