// Rolling alarm window (PLAN 7.1): keep the next 48 h plus the next N
// future alarms registered. Pure Dart; the native module mirrors this.
class AlarmCandidate {
  AlarmCandidate({
    required this.sourceType,
    required this.sourceId,
    required this.fireAtUtcMs,
    required this.preset,
  });

  final String sourceType;
  final String sourceId;
  final int fireAtUtcMs;
  final String preset;
}

class PlannedAlarm {
  PlannedAlarm({
    required this.sourceType,
    required this.sourceId,
    required this.fireAtUtcMs,
    required this.preset,
    required this.requestCode,
  });

  final String sourceType;
  final String sourceId;
  final int fireAtUtcMs;
  final String preset;
  final int requestCode;
}

/// Returns registrations ordered by fire time, capped at [maxFuture].
/// [presets] maps preset name to whether it needs setAlarmClock.
List<PlannedAlarm> planAlarmWindow(
  List<AlarmCandidate> candidates, {
  required int nowUtcMs,
  int horizonHours = 48,
  int maxFuture = 60,
}) {
  final horizonMs = nowUtcMs + horizonHours * 3600000;
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
      ),
  ];
}

/// Strong/constant presets need setAlarmClock; light uses exact-while-idle.
bool needsAlarmClock(String preset) =>
    preset == 'medium' || preset == 'strong' || preset == 'constant';
