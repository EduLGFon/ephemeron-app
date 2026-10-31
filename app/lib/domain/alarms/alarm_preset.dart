// Alarm presets: the three user-facing alarm styles.
// Reminders (early/at-time plain notifications) are separate; see
// domain/alarms/reminder.dart. An alarm fires at the item time with one
// of these styles. Widgets contain no logic; repositories map this to
// native scheduling.
enum AlarmPreset {
  notification('notification'),
  fullScreenShort('full_short'),
  fullScreenLong('full_long');

  const AlarmPreset(this.id);
  final String id;

  static AlarmPreset? tryParse(String? raw) {
    if (raw == null || raw.isEmpty || raw == 'none') return null;
    for (final p in AlarmPreset.values) {
      if (p.id == raw) return p;
    }
    return _legacyMap(raw);
  }

  static AlarmPreset? _legacyMap(String raw) {
    return switch (raw) {
      'light' => AlarmPreset.notification,
      'medium' => AlarmPreset.fullScreenShort,
      'strong' => AlarmPreset.fullScreenShort,
      'constant' => AlarmPreset.fullScreenLong,
      'habit' => AlarmPreset.notification,
      'focus' => AlarmPreset.notification,
      _ => null,
    };
  }
}

extension AlarmPresetInfo on AlarmPreset {
  String get title => switch (this) {
    AlarmPreset.notification => 'Notification',
    AlarmPreset.fullScreenShort => 'Full screen, short sound',
    AlarmPreset.fullScreenLong => 'Full screen, long sound',
  };

  String get description => switch (this) {
    AlarmPreset.notification => 'Notification with short sound.',
    AlarmPreset.fullScreenShort =>
      'Full-screen alert with short sound. '
          'While using your phone you get a notification instead.',
    AlarmPreset.fullScreenLong =>
      'Full-screen alert with constant long sound and vibration. '
          'While using your phone you get a notification instead. '
          'Repeats every minute until resolved.',
  };

  /// Full-screen presets use setAlarmClock (Doze-exempt, shows ring UI).
  /// Notification preset uses exact-while-idle.
  bool get needsAlarmClock => this != AlarmPreset.notification;

  bool get usesFullScreen => this != AlarmPreset.notification;

  bool get loopsSound => this == AlarmPreset.fullScreenLong;

  bool get vibrates => this == AlarmPreset.fullScreenLong;

  /// Long preset repeats every minute, capped at 30 minutes.
  int get maxRepeats => this == AlarmPreset.fullScreenLong ? 30 : 0;

  String get channelId => 'alarm_$id';
}

/// Parses a stored preset string (current or legacy) to [AlarmPreset].
/// Returns null when no alarm is set or the value is unknown.
AlarmPreset? parseAlarmPreset(String? raw) => AlarmPreset.tryParse(raw);
