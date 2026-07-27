import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared_preferences_provider.dart';

enum PowerSavingMode { auto, alwaysOn, alwaysOff }

/// Small, frequently-read app settings. Deliberately kept out of the Drift
/// database — this is the kind of data every screen touches on every
/// build (e.g. to decide whether to animate), so it lives in memory with
/// SharedPreferences as the persistence backstop, not in a SQL query path.
class AppSettings {
  const AppSettings({
    this.reducedMotion = false,
    this.powerSavingMode = PowerSavingMode.auto,
    this.osBatterySaverActive = false,
    this.usePillNavigation = true,
    this.calendarStartDay = 7, // Sunday by default (1=Mon..7=Sun)
    this.autoSync = true,
    this.syncIntervalMinutes = 30,
    this.alarmShortSoundPath =
        '/usr/share/sounds/ocean/stereo/alarm-clock-elapsed.oga',
    this.alarmLongSoundPath =
        '/usr/share/sounds/ocean/stereo/phone-incoming-call.oga',
    this.alarmBackground = '#005F73', // Petrol default hex color
    this.glassmorphismEnabled = false,
    this.hapticsEnabled = true,
    this.enabledDeviceCalendarIds = const {},
    this.animationsEnabled = true,
    this.backgroundSyncEnabled = true,
  });

  final bool reducedMotion;

  /// Manual user override — independent of what the OS itself reports.
  final PowerSavingMode powerSavingMode;

  /// Live-detected from the OS (see AppSettingsNotifier.refreshBatteryState)
  /// — never persisted, since it should reflect the device's *current*
  /// state each session, not whatever it happened to be last time the
  /// app ran.
  final bool osBatterySaverActive;

  final bool usePillNavigation;

  /// First day of the week for the Calendar view.
  /// Uses ISO weekday values: 1=Monday ... 7=Sunday.
  final int calendarStartDay;

  final bool autoSync;
  final int syncIntervalMinutes;

  final String alarmShortSoundPath;
  final String alarmLongSoundPath;
  final String alarmBackground;
  final bool glassmorphismEnabled;
  final bool hapticsEnabled;
  final Set<String> enabledDeviceCalendarIds;
  
  final bool animationsEnabled;
  final bool backgroundSyncEnabled;

  /// Effective "should we skip decorative animation" flag: the user's
  /// explicit toggle, their manual power-saving override, OR the OS
  /// actually reporting battery saver is on. Every animated widget in
  /// the app should check this, not [reducedMotion] alone.
  bool get shouldReduceMotion {
    if (reducedMotion) return true;
    switch (powerSavingMode) {
      case PowerSavingMode.alwaysOn: return true;
      case PowerSavingMode.alwaysOff: return false;
      case PowerSavingMode.auto: return osBatterySaverActive;
    }
  }

  AppSettings copyWith({
    bool? reducedMotion,
    PowerSavingMode? powerSavingMode,
    bool? osBatterySaverActive,
    bool? usePillNavigation,
    int? calendarStartDay,
    bool? autoSync,
    int? syncIntervalMinutes,
    String? alarmShortSoundPath,
    String? alarmLongSoundPath,
    String? alarmBackground,
    bool? glassmorphismEnabled,
    bool? hapticsEnabled,
    Set<String>? enabledDeviceCalendarIds,
    bool? animationsEnabled,
    bool? backgroundSyncEnabled,
  }) {
    return AppSettings(
      reducedMotion: reducedMotion ?? this.reducedMotion,
      powerSavingMode: powerSavingMode ?? this.powerSavingMode,
      osBatterySaverActive: osBatterySaverActive ?? this.osBatterySaverActive,
      usePillNavigation: usePillNavigation ?? this.usePillNavigation,
      calendarStartDay: calendarStartDay ?? this.calendarStartDay,
      autoSync: autoSync ?? this.autoSync,
      syncIntervalMinutes: syncIntervalMinutes ?? this.syncIntervalMinutes,
      alarmShortSoundPath: alarmShortSoundPath ?? this.alarmShortSoundPath,
      alarmLongSoundPath: alarmLongSoundPath ?? this.alarmLongSoundPath,
      alarmBackground: alarmBackground ?? this.alarmBackground,
      glassmorphismEnabled: glassmorphismEnabled ?? this.glassmorphismEnabled,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      enabledDeviceCalendarIds:
          enabledDeviceCalendarIds ?? this.enabledDeviceCalendarIds,
      animationsEnabled: animationsEnabled ?? this.animationsEnabled,
      backgroundSyncEnabled: backgroundSyncEnabled ?? this.backgroundSyncEnabled,
    );
  }
}

class AppSettingsNotifier extends Notifier<AppSettings> {
  static const _reducedMotionKey = 'settings.reducedMotion';
  static const _powerSavingKey = 'settings.powerSavingMode';
  static const _usePillNavigationKey = 'settings.usePillNavigation';
  static const _calendarStartDayKey = 'settings.calendarStartDay';
  static const _autoSyncKey = 'settings.autoSync';
  static const _syncIntervalMinutesKey = 'settings.syncIntervalMinutes';
  static const _alarmShortSoundPathKey = 'settings.alarmShortSoundPath';
  static const _alarmLongSoundPathKey = 'settings.alarmLongSoundPath';
  static const _alarmBackgroundKey = 'settings.alarmBackground';
  static const _glassmorphismEnabledKey = 'settings.glassmorphismEnabled';
  static const _hapticsEnabledKey = 'settings.hapticsEnabled';
  static const _enabledDeviceCalendarIdsKey =
      'settings.enabledDeviceCalendarIds';
  static const _animationsEnabledKey = 'settings.animationsEnabled';
  static const _backgroundSyncEnabledKey = 'settings.backgroundSyncEnabled';
  final _battery = Battery();

  @override
  AppSettings build() {
    refreshBatteryState();
    final sharedPrefs = ref.watch(sharedPreferencesProvider);
    
    PowerSavingMode mode = PowerSavingMode.auto;
    final modeString = sharedPrefs.getString(_powerSavingKey);
    if (modeString != null) {
      mode = PowerSavingMode.values.firstWhere((e) => e.name == modeString, orElse: () => PowerSavingMode.auto);
    }
    
    return AppSettings(
      reducedMotion: sharedPrefs.getBool(_reducedMotionKey) ?? false,
      powerSavingMode: mode,
      usePillNavigation: sharedPrefs.getBool(_usePillNavigationKey) ?? true,
      calendarStartDay: sharedPrefs.getInt(_calendarStartDayKey) ?? 7,
      autoSync: sharedPrefs.getBool(_autoSyncKey) ?? true,
      syncIntervalMinutes: sharedPrefs.getInt(_syncIntervalMinutesKey) ?? 30,
      alarmShortSoundPath: sharedPrefs.getString(_alarmShortSoundPathKey) ??
          '/usr/share/sounds/ocean/stereo/alarm-clock-elapsed.oga',
      alarmLongSoundPath: sharedPrefs.getString(_alarmLongSoundPathKey) ??
          '/usr/share/sounds/ocean/stereo/phone-incoming-call.oga',
      alarmBackground: sharedPrefs.getString(_alarmBackgroundKey) ?? '#005F73',
      glassmorphismEnabled: sharedPrefs.getBool(_glassmorphismEnabledKey) ?? false,
      hapticsEnabled: sharedPrefs.getBool(_hapticsEnabledKey) ?? true,
      enabledDeviceCalendarIds:
          (sharedPrefs.getStringList(_enabledDeviceCalendarIdsKey) ?? const [])
              .toSet(),
      animationsEnabled: sharedPrefs.getBool(_animationsEnabledKey) ?? true,
      backgroundSyncEnabled: sharedPrefs.getBool(_backgroundSyncEnabledKey) ?? true,
    );
  }

  /// Checks the OS's actual battery-saver state. Not available on every
  /// platform (notably web) — fails silently into "not active" rather
  /// than surfacing a platform-support error to the user over what's
  /// meant to be a quiet background convenience.
  Future<void> refreshBatteryState() async {
    if (kIsWeb) return;
    try {
      final isActive = await _battery.isInBatterySaveMode;
      state = state.copyWith(osBatterySaverActive: isActive);
    } catch (_) {
      // Unsupported on this platform/device — leave at the default
      // (false) rather than treat an unknown as "active".
    }
  }

  Future<void> setReducedMotion(bool value) async {
    state = state.copyWith(reducedMotion: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reducedMotionKey, value);
  }

  Future<void> setPowerSavingMode(PowerSavingMode value) async {
    state = state.copyWith(powerSavingMode: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_powerSavingKey, value.name);
  }

  Future<void> setUsePillNavigation(bool value) async {
    state = state.copyWith(usePillNavigation: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_usePillNavigationKey, value);
  }

  Future<void> setCalendarStartDay(int value) async {
    state = state.copyWith(calendarStartDay: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_calendarStartDayKey, value);
  }

  Future<void> setAutoSync(bool value) async {
    state = state.copyWith(autoSync: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSyncKey, value);
  }

  Future<void> setSyncIntervalMinutes(int value) async {
    state = state.copyWith(syncIntervalMinutes: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_syncIntervalMinutesKey, value);
  }

  Future<void> setAlarmShortSoundPath(String value) async {
    state = state.copyWith(alarmShortSoundPath: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_alarmShortSoundPathKey, value);
  }

  Future<void> setAlarmLongSoundPath(String value) async {
    state = state.copyWith(alarmLongSoundPath: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_alarmLongSoundPathKey, value);
  }

  Future<void> setAlarmBackground(String value) async {
    state = state.copyWith(alarmBackground: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_alarmBackgroundKey, value);
  }

  Future<void> setGlassmorphismEnabled(bool value) async {
    state = state.copyWith(glassmorphismEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_glassmorphismEnabledKey, value);
  }

  Future<void> setHapticsEnabled(bool value) async {
    state = state.copyWith(hapticsEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hapticsEnabledKey, value);
  }

  Future<void> setEnabledDeviceCalendarIds(Set<String> value) async {
    state = state.copyWith(enabledDeviceCalendarIds: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_enabledDeviceCalendarIdsKey, value.toList());
  }
  
  Future<void> setAnimationsEnabled(bool value) async {
    state = state.copyWith(animationsEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_animationsEnabledKey, value);
  }

  Future<void> setBackgroundSyncEnabled(bool value) async {
    state = state.copyWith(backgroundSyncEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_backgroundSyncEnabledKey, value);
  }
}

final appSettingsProvider =
    NotifierProvider<AppSettingsNotifier, AppSettings>(AppSettingsNotifier.new);
