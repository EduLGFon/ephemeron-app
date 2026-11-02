// Moment-of-need permission prompts. Nothing is asked upfront: each
// permission is requested only when the user reaches the feature that
// needs it, with a one-line reason first. Denials degrade to a snackbar
// with a one-tap link to system settings, never a crash or dead end.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/alarms/data/alarm_scheduler.dart';
import 'system_launcher.dart';

class AppPermissions {
  const AppPermissions._();

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Notifications: asked when the first reminder/alarm is saved or tested.
  /// Returns true when alerts can be shown.
  static Future<bool> ensureNotifications(
    BuildContext context, {
    String reason =
        'Allow notifications so reminders and alarms can ring on time.',
  }) async {
    if (!_isAndroid) return true;
    if (await SystemLauncher.canPostNotifications()) return true;
    if (!context.mounted) return false;
    final allow = await _explainer(
      context,
      title: 'Notifications',
      body: reason,
      actionLabel: 'Allow',
    );
    if (allow != true) return false;
    final granted = await SystemLauncher.requestNotifications();
    if (granted) return true;
    if (!context.mounted) return false;
    _deniedSnack(
      context,
      'Notifications denied. Alarms are saved but may stay silent.',
    );
    return false;
  }

  /// Exact alarms: asked when an alarm/reminder is saved or tested and the
  /// OS reports the privilege missing. Opens system settings (special
  /// permission, no inline dialog possible).
  static Future<bool> ensureExactAlarm(BuildContext context) async {
    if (!_isAndroid) return true;
    if (await AlarmScheduler.canScheduleExact()) return true;
    if (!context.mounted) return false;
    final open = await _explainer(
      context,
      title: 'Exact alarms',
      body:
          'Android needs exact-alarm access to ring at the set time, '
          'including in power saving. This opens system settings.',
      actionLabel: 'Open settings',
    );
    if (open == true) await AlarmScheduler.openExactAlarmSettings();
    return false;
  }

  /// Full-screen intent: asked only when a full-screen preset is used or
  /// tested on Android 14+. Below 14 it is always granted.
  static Future<bool> ensureFullScreenIntent(
    BuildContext context, {
    bool needed = false,
  }) async {
    if (!_isAndroid || !needed) return true;
    if (await SystemLauncher.canUseFullScreenIntent()) return true;
    if (!context.mounted) return false;
    final open = await _explainer(
      context,
      title: 'Full-screen alarms',
      body:
          'Full-screen alarms can show over the lock screen. '
          'This opens system settings to allow it.',
      actionLabel: 'Open settings',
    );
    if (open == true) await SystemLauncher.openFullScreenSettings();
    return false;
  }

  /// Combined alarm pre-requisites for a save/start with [preset] semantics:
  /// notifications always, exact alarms for clock presets, full-screen for
  /// lock-screen presets. Advisory only; callers save regardless.
  /// Call with no prior await in the caller, then check `mounted` after.
  static Future<void> ensureAlarmPrereqs(
    BuildContext context, {
    bool exactAlarm = false,
    bool fullScreen = false,
  }) async {
    await ensureNotifications(context);
    if (!context.mounted) return;
    if (exactAlarm) await ensureExactAlarm(context);
    if (!context.mounted) return;
    await ensureFullScreenIntent(context, needed: fullScreen);
  }

  /// Calendar import explainer shown before the OS calendar prompt, which
  /// device_calendar_plus displays itself. Returns true to proceed.
  static Future<bool> explainCalendarImport(BuildContext context) async {
    final proceed = await _explainer(
      context,
      title: 'Import device calendars?',
      body:
          'Ephemeron reads your chosen device calendars once and copies '
          'their events into a local app calendar. Nothing is uploaded.',
      actionLabel: 'Continue',
    );
    return proceed == true;
  }

  static Future<bool?> _explainer(
    BuildContext context, {
    required String title,
    required String body,
    required String actionLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  static void _deniedSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        persist: false,
        action: SnackBarAction(
          label: 'Settings',
          onPressed: SystemLauncher.openAppSettings,
        ),
      ),
    );
  }
}
