// SharedPreferences-backed store for the single active habit stopwatch timer.
// No Drift schema change: only SharedPreferences keys.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HabitTimer {
  const HabitTimer({
    required this.habitId,
    required this.dayKey,
    required this.startedAtMs,
  });

  final String habitId;
  final String dayKey;
  final int startedAtMs;
}

class HabitTimerStore {
  HabitTimerStore(this._prefs) {
    active.value = _read();
  }

  final SharedPreferences _prefs;
  final ValueNotifier<HabitTimer?> active = ValueNotifier<HabitTimer?>(null);

  static const _kHabitId = 'habit_timer.habitId';
  static const _kDayKey = 'habit_timer.dayKey';
  static const _kStartedAt = 'habit_timer.startedAtMs';

  HabitTimer? _read() {
    final habitId = _prefs.getString(_kHabitId);
    final dayKey = _prefs.getString(_kDayKey);
    final startedAt = _prefs.getInt(_kStartedAt);
    if (habitId == null || dayKey == null || startedAt == null) return null;
    return HabitTimer(habitId: habitId, dayKey: dayKey, startedAtMs: startedAt);
  }

  Future<void> start(String habitId, String dayKey, int startedAtMs) async {
    await _prefs.setString(_kHabitId, habitId);
    await _prefs.setString(_kDayKey, dayKey);
    await _prefs.setInt(_kStartedAt, startedAtMs);
    active.value = HabitTimer(
      habitId: habitId,
      dayKey: dayKey,
      startedAtMs: startedAtMs,
    );
  }

  Future<void> clear() async {
    await _prefs.remove(_kHabitId);
    await _prefs.remove(_kDayKey);
    await _prefs.remove(_kStartedAt);
    active.value = null;
  }
}
