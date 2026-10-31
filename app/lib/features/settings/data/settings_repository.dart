import 'package:shared_preferences/shared_preferences.dart';

enum PowerSavingMode { auto, on, off }

class SettingsRepository {
  SettingsRepository(this._prefs);
  final SharedPreferences _prefs;

  static const _kPrimary = 'settings.primaryColor';
  static const _kBackground = 'settings.backgroundColor';
  static const _kBrightness = 'settings.brightness';
  static const _kNavOrder = 'settings.navOrder';
  static const _kPower = 'settings.powerSaving';
  static const _kReduceAnim = 'settings.reduceAnimations';
  static const _kHaptics = 'settings.haptics';
  static const _kOnboarded = 'settings.onboarded';
  static const _kLocale = 'settings.locale';

  String? get primaryColorHex => _prefs.getString(_kPrimary);
  Future<void> setPrimaryColorHex(String v) => _prefs.setString(_kPrimary, v);

  String? get backgroundColorHex => _prefs.getString(_kBackground);
  Future<void> setBackgroundColorHex(String v) =>
      _prefs.setString(_kBackground, v);

  String get brightness => _prefs.getString(_kBrightness) ?? 'light';
  Future<void> setBrightness(String v) => _prefs.setString(_kBrightness, v);

  List<int> get navOrder {
    final raw = _prefs.getStringList(_kNavOrder);
    if (raw == null) return List<int>.generate(7, (i) => i);
    return raw.map(int.parse).toList();
  }

  Future<void> setNavOrder(List<int> order) =>
      _prefs.setStringList(_kNavOrder, order.map((e) => e.toString()).toList());

  PowerSavingMode get powerSavingMode {
    final v = _prefs.getString(_kPower) ?? 'auto';
    return PowerSavingMode.values.firstWhere(
      (e) => e.name == v,
      orElse: () => PowerSavingMode.auto,
    );
  }

  Future<void> setPowerSavingMode(PowerSavingMode m) =>
      _prefs.setString(_kPower, m.name);

  bool get reduceAnimations => _prefs.getBool(_kReduceAnim) ?? false;
  Future<void> setReduceAnimations(bool v) => _prefs.setBool(_kReduceAnim, v);

  bool get haptics => _prefs.getBool(_kHaptics) ?? true;
  Future<void> setHaptics(bool v) => _prefs.setBool(_kHaptics, v);

  bool get onboarded => _prefs.getBool(_kOnboarded) ?? false;
  Future<void> setOnboarded() => _prefs.setBool(_kOnboarded, true);

  /// 'system', 'en' or 'pt'.
  String get localeCode => _prefs.getString(_kLocale) ?? 'system';
  Future<void> setLocaleCode(String v) => _prefs.setString(_kLocale, v);

  static const _kLastTab = 'session.lastTab';
  int get lastTabIndex => _prefs.getInt(_kLastTab) ?? 0;
  Future<void> setLastTabIndex(int v) => _prefs.setInt(_kLastTab, v);

  static const _kCalView = 'calendar.view';
  String get calendarView => _prefs.getString(_kCalView) ?? 'month';
  Future<void> setCalendarView(String v) => _prefs.setString(_kCalView, v);

  static const _kWeekStart = 'calendar.weekStart';
  int get weekStart => _prefs.getInt(_kWeekStart) ?? DateTime.monday;
  Future<void> setWeekStart(int v) => _prefs.setInt(_kWeekStart, v);

  static const _kDefaultCal = 'calendar.defaultId';
  String? get defaultCalendarId => _prefs.getString(_kDefaultCal);
  Future<void> setDefaultCalendarId(String v) =>
      _prefs.setString(_kDefaultCal, v);

  static const _kDefaultDur = 'calendar.defaultDurationMin';
  int get defaultDurationMin => _prefs.getInt(_kDefaultDur) ?? 60;
  Future<void> setDefaultDurationMin(int v) => _prefs.setInt(_kDefaultDur, v);

  /// Google auto-sync interval in minutes. 0 means disabled.
  static const _kSyncInterval = 'sync.intervalMin';
  int get syncIntervalMin => _prefs.getInt(_kSyncInterval) ?? 30;
  Future<void> setSyncIntervalMin(int v) => _prefs.setInt(_kSyncInterval, v);

  /// Focus: enable alarms-only DND while a session runs (Android only,
  /// needs notification-policy access granted in system settings).
  static const _kFocusDnd = 'focus.dnd';
  bool get focusDnd => _prefs.getBool(_kFocusDnd) ?? false;
  Future<void> setFocusDnd(bool v) => _prefs.setBool(_kFocusDnd, v);

  /// Backend habits/focus auto-sync interval in minutes. 0 means manual.
  static const _kBackendSyncInterval = 'sync.backendIntervalMin';
  int get backendSyncIntervalMin => _prefs.getInt(_kBackendSyncInterval) ?? 0;
  Future<void> setBackendSyncIntervalMin(int v) =>
      _prefs.setInt(_kBackendSyncInterval, v);

  /// Optional biometric app lock (PLAN 8.4). Gate only, no datasegregation change.
  static const _kBiometricLock = 'security.biometricLock';
  bool get biometricLock => _prefs.getBool(_kBiometricLock) ?? false;
  Future<void> setBiometricLock(bool v) => _prefs.setBool(_kBiometricLock, v);

  /// Last successful Google sync, for title freshness + scheduling.
  static const _kLastGoogleSync = 'sync.lastGoogleSyncAtMs';
  DateTime? get lastGoogleSyncAt {
    final ms = _prefs.getInt(_kLastGoogleSync);
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  Future<void> setLastGoogleSyncAt(DateTime? v) => v == null
      ? _prefs.remove(_kLastGoogleSync)
      : _prefs.setInt(_kLastGoogleSync, v.toUtc().millisecondsSinceEpoch);
}
