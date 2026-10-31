import 'package:ephemeron/core/time/time.dart';
import 'alarm_preset.dart';

// Rolling alarm window (PLAN 7.1): keep the next 48 h plus the next N
// future alarms registered. Pure Dart; the native module mirrors this.
// Reminders (kind=reminder) and alarms (kind=alarm) share the window.
class AlarmCandidate {
  AlarmCandidate({
    required this.sourceType,
    required this.sourceId,
    required this.fireAtUtcMs,
    required this.preset,
    this.kind = 'alarm',
    this.title = '',
  });

  final String sourceType;
  final String sourceId;
  final int fireAtUtcMs;
  final String preset;
  final String kind;
  final String title;
}

class PlannedAlarm {
  PlannedAlarm({
    required this.sourceType,
    required this.sourceId,
    required this.fireAtUtcMs,
    required this.preset,
    required this.requestCode,
    this.kind = 'alarm',
    this.title = '',
  });

  final String sourceType;
  final String sourceId;
  final int fireAtUtcMs;
  final String preset;
  final int requestCode;
  final String kind;
  final String title;
}

/// Returns registrations ordered by fire time, capped at [maxFuture].
List<PlannedAlarm> planAlarmWindow(
  List<AlarmCandidate> candidates, {
  required int nowUtcMs,
  int horizonHours = 48,
  int maxFuture = 60,
}) {
  final horizonMs = nowUtcMs + horizonHours * msPerHour;
  final future = candidates.where((c) => c.fireAtUtcMs > nowUtcMs).toList()
    ..sort((a, b) => a.fireAtUtcMs.compareTo(b.fireAtUtcMs));
  final inHorizon = future.where((c) => c.fireAtUtcMs <= horizonMs).toList();
  final beyond = future
      .where((c) => c.fireAtUtcMs > horizonMs)
      .take(maxFuture)
      .toList();
  final picked = [...inHorizon, ...beyond];
  return [
    for (var i = 0; i < picked.length; i++)
      PlannedAlarm(
        sourceType: picked[i].sourceType,
        sourceId: picked[i].sourceId,
        fireAtUtcMs: picked[i].fireAtUtcMs,
        preset: picked[i].preset,
        requestCode: 100000 + i,
        kind: picked[i].kind,
        title: picked[i].title,
      ),
  ];
}

/// Full-screen presets need setAlarmClock; notification uses exact-idle.
bool needsAlarmClock(String preset) {
  final p = AlarmPreset.tryParse(preset);
  if (p != null) return p.needsAlarmClock;
  return preset == 'medium' || preset == 'strong' || preset == 'constant';
}

bool usesFullScreen(String preset) {
  final p = AlarmPreset.tryParse(preset);
  if (p != null) return p.usesFullScreen;
  return preset == 'medium' || preset == 'strong' || preset == 'constant';
}
