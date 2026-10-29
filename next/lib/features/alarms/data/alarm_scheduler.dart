import '../domain/alarm_preset.dart';
import '../domain/reminder_offset.dart';

class AlarmScheduler {
  Future<List<int>> scheduleAlarmsForOffsets({
    required String entityId,
    required String title,
    required String body,
    required DateTime dueAt,
    required List<ReminderOffset> offsets,
    required AlarmPreset preset,
  }) async {
    return <int>[];
  }

  Future<void> cancelByIds(List<int> ids) async {}
}