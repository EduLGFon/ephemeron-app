import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local/database.dart';
import '../../alarms/data/alarm_scheduler.dart';
import '../../alarms/domain/alarm_preset.dart';
import '../../alarms/domain/reminder_offset.dart';
import '../domain/countdown_type.dart';

const _uuid = Uuid();

/// Fixed per the brainstorm ("All countdowns have alert setted by
/// default to 3 days before and at the day") — unlike Tasks/Events,
/// countdown alerts aren't user-configurable in this MVP step, so there's
/// no preset/offset picker in the UI and no per-countdown override here.
const _defaultOffsets = [ReminderOffset.atTime];
final _defaultOffsetsWithLeadTime = [
  ReminderOffset.custom(const Duration(days: 3)),
  ReminderOffset.atTime,
];

class CountdownRepository {
  CountdownRepository(this._db, this._alarmScheduler);

  final AppDatabase _db;
  final AlarmScheduler _alarmScheduler;

  Stream<List<Countdown>> watchCountdowns() =>
      _db.select(_db.countdowns).watch();

  Future<Countdown> createCountdown({
    required String title,
    required CountdownType type,
    required DateTime targetDate,
    bool? isYearly,
    bool showAge = false,
  }) async {
    final id = _uuid.v4();
    await _db
        .into(_db.countdowns)
        .insert(
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
    return (_db.select(
      _db.countdowns,
    )..where((c) => c.id.equals(id))).getSingle();
  }

  Future<void> updateCountdown(
    String countdownId, {
    String? title,
    DateTime? targetDate,
    bool? isYearly,
    bool? showAge,
  }) async {
    await (_db.update(
      _db.countdowns,
    )..where((c) => c.id.equals(countdownId))).write(
      CountdownsCompanion(
        title: title != null ? Value(title) : const Value.absent(),
        targetDate: targetDate != null
            ? Value(targetDate)
            : const Value.absent(),
        isYearly: isYearly != null ? Value(isYearly) : const Value.absent(),
        showAge: showAge != null ? Value(showAge) : const Value.absent(),
      ),
    );
    await _syncAlarms(countdownId);
  }

  Future<void> deleteCountdown(String countdownId) async {
    final countdown = await (_db.select(
      _db.countdowns,
    )..where((c) => c.id.equals(countdownId))).getSingleOrNull();
    if (countdown != null) await _cancelAlarms(countdown);
    await (_db.delete(
      _db.countdowns,
    )..where((c) => c.id.equals(countdownId))).go();
  }

  Future<void> _cancelAlarms(Countdown countdown) async {
    final ids = _decodeIds(countdown.scheduledAlarmIds);
    if (ids.isNotEmpty) await _alarmScheduler.cancelByIds(ids);
  }

  /// Schedules against the next occurrence (this year's date if it
  /// hasn't passed, else next year's, for yearly countdowns — the exact
  /// date for one-off custom countdowns). Yearly countdowns need
  /// [refreshYearlyAlarms] called periodically to roll forward once the
  /// current year's occurrence has passed, the same pattern Habits'
  /// weekly/interval one-shot alarms use and for the same underlying
  /// reason: there's no native "once a year" OS recurrence rule to peg
  /// this to the way there is for daily.
  Future<void> _syncAlarms(String countdownId) async {
    final countdown = await (_db.select(
      _db.countdowns,
    )..where((c) => c.id.equals(countdownId))).getSingleOrNull();
    if (countdown == null) return;

    final existingIds = _decodeIds(countdown.scheduledAlarmIds);
    if (existingIds.isNotEmpty) await _alarmScheduler.cancelByIds(existingIds);

    final occurrence = _nextOccurrence(countdown);
    final offsets = _offsetsFor(occurrence);
    final newIds = await _alarmScheduler.scheduleAlarmsForOffsets(
      entityId: countdown.id,
      title: countdown.title,
      body: '',
      dueAt: occurrence,
      offsets: offsets,
      preset: AlarmPreset.light,
    );

    await (_db.update(
      _db.countdowns,
    )..where((c) => c.id.equals(countdownId))).write(
      CountdownsCompanion(
        scheduledAlarmIds: Value(newIds.isEmpty ? null : jsonEncode(newIds)),
      ),
    );
  }

  /// Only include the 3-day lead-time reminder if there's actually more
  /// than 3 days left — otherwise it would compute to a moment already
  /// in the past and scheduleAlarmsForOffsets silently skips it anyway,
  /// but there's no reason to even try.
  List<ReminderOffset> _offsetsFor(DateTime occurrence) {
    final daysUntil = occurrence.difference(DateTime.now()).inDays;
    return daysUntil > 3 ? _defaultOffsetsWithLeadTime : _defaultOffsets;
  }

  DateTime _nextOccurrence(Countdown countdown) {
    if (!countdown.isYearly) return countdown.targetDate;
    final today = DateTime.now();
    var occurrence = DateTime(
      today.year,
      countdown.targetDate.month,
      countdown.targetDate.day,
      9,
    );
    if (occurrence.isBefore(today)) {
      occurrence = DateTime(
        today.year + 1,
        countdown.targetDate.month,
        countdown.targetDate.day,
        9,
      );
    }
    return occurrence;
  }

  /// Re-syncs every yearly countdown's alarms — cheap no-op for ones
  /// whose current occurrence hasn't passed yet (cancel-then-reschedule
  /// against the same date), and rolls the rest forward to next year.
  /// Call from app startup, same spot as Habits' equivalent.
  Future<void> refreshYearlyAlarms() async {
    final countdowns = await watchCountdowns().first;
    for (final countdown in countdowns) {
      if (countdown.isYearly) await _syncAlarms(countdown.id);
    }
  }

  List<int> _decodeIds(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return (jsonDecode(raw) as List<dynamic>).cast<int>();
  }
}
