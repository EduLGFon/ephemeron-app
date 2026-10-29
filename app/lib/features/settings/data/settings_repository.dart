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
}
