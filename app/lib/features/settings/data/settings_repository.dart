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

  /// Last top-level route for session restore (`/tab0`..`/tab6`,
  /// `/search`, `/settings`, `/alarm-settings`, `note:<id>`).
  static const _kLastRoute = 'session.lastRoute';
  String? get lastRoute => _prefs.getString(_kLastRoute);
  Future<void> setLastRoute(String? v) =>
      v == null ? _prefs.remove(_kLastRoute) : _prefs.setString(_kLastRoute, v);

  /// Open sheet/modal descriptor persisted across restarts so unsaved
  /// work is never lost. Values like `quick_add`, `task_new`,
  /// `task:[id]`, `event_new`, `event:[id]`, `event_details:[id]`,
  /// `habit_new`, `habit:[id]`, `countdown_new`, `countdown:[id]`,
  /// `note:[id]`. Null means no sheet was open.
  static const _kOpenSheet = 'session.openSheet';
  static const _kOpenSheetAt = 'session.openSheetAtMs';
  String? get openSheet => _prefs.getString(_kOpenSheet);
  int? get openSheetAtMs => _prefs.getInt(_kOpenSheetAt);
  Future<void> setOpenSheet(String? type) async {
    if (type == null) {
      await _prefs.remove(_kOpenSheet);
      await _prefs.remove(_kOpenSheetAt);
    } else {
      await _prefs.setString(_kOpenSheet, type);
      await _prefs.setInt(
        _kOpenSheetAt,
        DateTime.now().toUtc().millisecondsSinceEpoch,
      );
    }
  }

  static const _kCalAnchor = 'calendar.anchorMs';
  int? get calendarAnchorMs => _prefs.getInt(_kCalAnchor);
  Future<void> setCalendarAnchorMs(int v) => _prefs.setInt(_kCalAnchor, v);

  static const _kCalDayCount = 'calendar.dayCount';
  int get calendarDayCount => _prefs.getInt(_kCalDayCount) ?? 1;
  Future<void> setCalendarDayCount(int v) => _prefs.setInt(_kCalDayCount, v);

  static const _kTaskList = 'tasks.selectedList';
  String? get selectedTaskListId => _prefs.getString(_kTaskList);
  Future<void> setSelectedTaskListId(String? v) =>
      v == null ? _prefs.remove(_kTaskList) : _prefs.setString(_kTaskList, v);

  /// Matrix board grouping: 'auto' (default) or 'priority'.
  static const _kMatrixMode = 'matrix.mode';
  String get matrixMode => _prefs.getString(_kMatrixMode) ?? 'auto';
  Future<void> setMatrixMode(String v) => _prefs.setString(_kMatrixMode, v);

  static const _kNotesFolder = 'notes.selectedFolder';
  String? get selectedNotesFolderId => _prefs.getString(_kNotesFolder);
  Future<void> setSelectedNotesFolderId(String? v) => v == null
      ? _prefs.remove(_kNotesFolder)
      : _prefs.setString(_kNotesFolder, v);

  static const _kSearchQuery = 'search.query';
  String get searchQuery => _prefs.getString(_kSearchQuery) ?? '';
  Future<void> setSearchQuery(String v) => _prefs.setString(_kSearchQuery, v);

  static const _kSearchScope = 'search.scope';
  String get searchScope => _prefs.getString(_kSearchScope) ?? 'all';
  Future<void> setSearchScope(String v) => _prefs.setString(_kSearchScope, v);

  /// Focus start-view options (lightweight, prefs not drafts).
  static const _kFocusMin = 'focus.setupMin';
  static const _kBreakMin = 'focus.breakMin';
  static const _kFocusIsBreak = 'focus.isBreak';
  static const _kFocusTask = 'focus.taskId';
  static const _kFocusHabit = 'focus.habitId';
  int get focusSetupMin => _prefs.getInt(_kFocusMin) ?? 25;
  int get focusBreakMin => _prefs.getInt(_kBreakMin) ?? 5;
  bool get focusIsBreak => _prefs.getBool(_kFocusIsBreak) ?? false;
  String? get focusTaskId => _prefs.getString(_kFocusTask);
  String? get focusHabitId => _prefs.getString(_kFocusHabit);
  Future<void> setFocusSetup({
    int? focusMin,
    int? breakMin,
    bool? isBreak,
    String? Function()? taskId,
    String? Function()? habitId,
  }) async {
    if (focusMin != null) await _prefs.setInt(_kFocusMin, focusMin);
    if (breakMin != null) await _prefs.setInt(_kBreakMin, breakMin);
    if (isBreak != null) await _prefs.setBool(_kFocusIsBreak, isBreak);
    if (taskId != null) {
      final v = taskId();
      if (v == null) {
        await _prefs.remove(_kFocusTask);
      } else {
        await _prefs.setString(_kFocusTask, v);
      }
    }
    if (habitId != null) {
      final v = habitId();
      if (v == null) {
        await _prefs.remove(_kFocusHabit);
      } else {
        await _prefs.setString(_kFocusHabit, v);
      }
    }
  }

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
