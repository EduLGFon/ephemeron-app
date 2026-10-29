import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local/database.dart';
import '../../alarms/data/alarm_scheduler.dart';
import '../../alarms/domain/alarm_preset.dart';
import '../../alarms/domain/reminder_offset.dart';
import '../domain/countdown_type.dart';

const _uuid = Uuid();

const _defaultOffsets = [ReminderOffset.atTime];

class CountdownRepository {
  CountdownRepository(this._db, this._alarmScheduler);

  final AppDatabase _db;
  final AlarmScheduler _alarmScheduler;

  Stream<List<Countdown>> watchCountdowns() => _db.select(_db.countdowns).watch();

  Future<Countdown> createCountdown({
    required String title,
    required CountdownType type,
    required DateTime targetDate,
    bool? isYearly,
    bool showAge = false,
  }) async {
    final id = _uuid.v4();
    await _db.into(_db.countdowns).insert(
          CountdownsCompanion.insert(
            id: Value(id),
            title: title,
            type: Value(type.name),
            targetDate: targetDate,
            isYearly: Value(isYearly ?? type.isYearlyByDefault),
            showAge: Value(showAge),
          ),
        );
    await _syncAlarms(id);
    return (_db.select(_db.countdowns)..where((c) => c.id.equals(id)))
        .getSingle();
  }

  Future<void> updateCountdown(
    String countdownId, {
    String? title,
    DateTime? targetDate,
    bool? isYearly,
    bool? showAge,
  }) async {
    await (_db.update(_db.countdowns)..where((c) => c.id.equals(countdownId)))
        .write(
      CountdownsCompanion(
        title: title != null ? Value(title) : const Value.absent(),
        targetDate:
            targetDate != null ? Value(targetDate) : const Value.absent(),
        isYearly: isYearly != null ? Value(isYearly) : const Value.absent(),
        showAge: showAge != null ? Value(showAge) : const Value.absent(),
      ),
    );
    await _syncAlarms(countdownId);
  }

  Future<void> _syncAlarms(String countdownId) async {
    final countdown = await (_db.select(_db.countdowns)
          ..where((c) => c.id.equals(countdownId)))
        .getSingleOrNull();
    if (countdown == null) return;

    final existingIds = _decodeIds(countdown.scheduledAlarmIds);
    if (existingIds.isNotEmpty) await _alarmScheduler.cancelByIds(existingIds);

    final occurrence = countdown.isYearly
        ? _nextOccurrence(countdown)
        : countdown.targetDate;
    final newIds = await _alarmScheduler.scheduleAlarmsForOffsets(
      entityId: countdown.id,
      title: countdown.title,
      body: '',
      dueAt: occurrence,
      offsets: _defaultOffsets,
      preset: AlarmPreset.light,
    );

    await (_db.update(_db.countdowns)..where((c) => c.id.equals(countdownId)))
        .write(
      CountdownsCompanion(
        scheduledAlarmIds: Value(newIds.isEmpty ? null : jsonEncode(newIds)),
      ),
    );
  }

  DateTime _nextOccurrence(Countdown countdown) {
    final today = DateTime.now();
    var occurrence = DateTime(
      today.year,
      countdown.targetDate.month,
      countdown.targetDate.day,
    );
    if (occurrence.isBefore(today)) {
      occurrence = DateTime(
        today.year + 1,
        countdown.targetDate.month,
        countdown.targetDate.day,
      );
    }
    return occurrence;
  }

  List<int> _decodeIds(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return (jsonDecode(raw) as List<dynamic>).cast<int>();
  }
}