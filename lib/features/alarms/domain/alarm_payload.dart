import 'dart:convert';

import '../domain/alarm_preset.dart';

/// Everything a notification tap/action callback needs to act on an
/// alarm, self-contained enough to survive being decoded in a background
/// isolate with no access to Riverpod/Drift (see alarm_scheduler.dart's
/// notificationTapBackground for why that constraint matters).
class AlarmPayload {
  const AlarmPayload({
    required this.entityId,
    required this.title,
    required this.body,
    required this.preset,
    this.siblingIds = const [],
  });

  final String entityId;
  final String title;
  final String body;
  final AlarmPreset preset;

  /// Notification IDs of every other offset-alarm scheduled for the same
  /// entity (e.g. "1h before" and "at the time" for one task) — carried
  /// along so a "Done" tap can cancel all of them without needing
  /// external state, including from the background isolate.
  final List<int> siblingIds;

  String encode() => jsonEncode({
        'entityId': entityId,
        'title': title,
        'body': body,
        'preset': preset.name,
        'siblingIds': siblingIds,
      });

  static AlarmPayload? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return AlarmPayload(
        entityId: map['entityId'] as String,
        title: map['title'] as String,
        body: map['body'] as String,
        preset: AlarmPreset.values.byName(map['preset'] as String),
        siblingIds: (map['siblingIds'] as List<dynamic>? ?? [])
            .map((e) => e as int)
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }
}
