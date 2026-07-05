/// How long before a due date/time a reminder should fire. Multiple
/// offsets can be attached to the same task/event/habit — e.g. both
/// "1h before" and "at the time" — so callers work with a `List<
/// ReminderOffset>`, not a single value.
class ReminderOffset {
  const ReminderOffset._(this.beforeDue, this.label);

  factory ReminderOffset.custom(Duration beforeDue) =>
      ReminderOffset._(beforeDue, _customLabel(beforeDue));

  final Duration beforeDue;
  final String label;

  static const atTime = ReminderOffset._(Duration.zero, 'At the time');
  static const fiveMinBefore = ReminderOffset._(Duration(minutes: 5), '5 min before');
  static const tenMinBefore = ReminderOffset._(Duration(minutes: 10), '10 min before');
  static const fifteenMinBefore = ReminderOffset._(Duration(minutes: 15), '15 min before');
  static const thirtyMinBefore = ReminderOffset._(Duration(minutes: 30), '30 min before');
  static const oneHourBefore = ReminderOffset._(Duration(hours: 1), '1 hour before');
  static const twoHoursBefore = ReminderOffset._(Duration(hours: 2), '2 hours before');

  static const presets = [
    atTime,
    fiveMinBefore,
    tenMinBefore,
    fifteenMinBefore,
    thirtyMinBefore,
    oneHourBefore,
    twoHoursBefore,
  ];

  /// Stable index used to build deterministic notification IDs (see
  /// alarm_scheduler.dart) — a custom offset always sorts after every
  /// preset regardless of its actual duration, so IDs stay stable even
  /// if presets are reordered above.
  int get presetIndex {
    final index = presets.indexWhere((p) => p.beforeDue == beforeDue && p.label == label);
    return index == -1 ? presets.length : index;
  }

  /// Reconstructs a [ReminderOffset] from a stored minutes value —
  /// matches back to the original preset by duration when possible, so
  /// round-tripping through storage doesn't turn presets into customs.
  factory ReminderOffset.fromMinutes(int minutes) {
    final duration = Duration(minutes: minutes);
    for (final preset in presets) {
      if (preset.beforeDue == duration) return preset;
    }
    return ReminderOffset.custom(duration);
  }

  static String _customLabel(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} min before';
    if (d.inHours < 24) return '${d.inHours}h before';
    return '${d.inDays}d before';
  }
}
