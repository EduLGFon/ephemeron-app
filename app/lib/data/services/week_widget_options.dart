// Global options for the week calendar home-screen widget.
// Persisted in SharedPreferences so the native provider, the foreground
// renderer, and restarts share one anchor/range. One global config is used
// (not per widget instance) because appWidgetId is not reliably available
// on the Dart side; documented limitation.
import 'package:shared_preferences/shared_preferences.dart';

/// Week widget background treatment.
enum WeekWidgetTheme {
  light,
  dark,
  transparent;

  static WeekWidgetTheme parse(String? raw) {
    switch (raw) {
      case 'dark':
        return WeekWidgetTheme.dark;
      case 'transparent':
        return WeekWidgetTheme.transparent;
      case 'light':
        return WeekWidgetTheme.light;
      default:
        return WeekWidgetTheme.light;
    }
  }

  String get key => name;
}

/// Day counts offered by the widget configuration UI.
const List<int> weekWidgetDayOptions = <int>[1, 3, 5, 7];

class WeekWidgetOptions {
  const WeekWidgetOptions({
    this.theme = WeekWidgetTheme.light,
    this.dayCount = 7,
    this.anchorDayKey,
  });

  static const String themeKey = 'week_calendar_theme';
  static const String dayCountKey = 'week_calendar_day_count';
  static const String anchorKey = 'week_calendar_anchor';

  final WeekWidgetTheme theme;
  final int dayCount;
  // Start of the shown range as yyyy-MM-dd, or null for current week/today.
  final String? anchorDayKey;

  WeekWidgetOptions copyWith({
    WeekWidgetTheme? theme,
    int? dayCount,
    String? Function()? anchorDayKey,
  }) {
    return WeekWidgetOptions(
      theme: theme ?? this.theme,
      dayCount: dayCount ?? this.dayCount,
      anchorDayKey: anchorDayKey == null ? this.anchorDayKey : anchorDayKey(),
    );
  }

  static int sanitizeDayCount(int value) =>
      weekWidgetDayOptions.contains(value) ? value : 7;

  /// yyyy-MM-dd for a date (local calendar day).
  static String dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static DateTime? tryParseDayKey(String raw) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw.trim());
    if (m == null) return null;
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    try {
      final dt = DateTime(y, mo, d);
      if (dt.year != y || dt.month != mo || dt.day != d) return null;
      return dt;
    } catch (_) {
      return null;
    }
  }

  /// Shifts an anchor by one visible span ([dayCount] days) in [direction].
  static DateTime shiftAnchor(DateTime anchor, int dayCount, int direction) {
    final span = sanitizeDayCount(dayCount);
    final base = DateTime(anchor.year, anchor.month, anchor.day);
    return base.add(Duration(days: span * direction));
  }

  static Future<WeekWidgetOptions> load([SharedPreferences? prefs]) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    final dayCount = sanitizeDayCount(p.getInt(dayCountKey) ?? 7);
    final anchor = p.getString(anchorKey);
    return WeekWidgetOptions(
      theme: WeekWidgetTheme.parse(p.getString(themeKey)),
      dayCount: dayCount,
      anchorDayKey: (anchor == null || anchor.isEmpty) ? null : anchor,
    );
  }

  Future<void> save([SharedPreferences? prefs]) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    await p.setString(themeKey, theme.key);
    await p.setInt(dayCountKey, sanitizeDayCount(dayCount));
    if (anchorDayKey == null || anchorDayKey!.isEmpty) {
      await p.remove(anchorKey);
    } else {
      await p.setString(anchorKey, anchorDayKey!);
    }
  }
}

/// What a `calendar/...` widget action asks the app to do.
enum WeekWidgetNav { today, prev, next, day }

class WeekWidgetTap {
  const WeekWidgetTap(this.nav, this.day);
  final WeekWidgetNav nav;
  // Set only for [WeekWidgetNav.day].
  final DateTime? day;
}

/// Parses the action suffix stored by MainActivity (the part after
/// `ephemeron://widget/`). Returns null for unrelated actions.
WeekWidgetTap? parseWeekWidgetAction(String? action) {
  if (action == null || action.isEmpty) return null;
  if (action == 'new_task' || action == 'search') return null;
  if (action == 'calendar' || action == 'calendar/today') {
    return const WeekWidgetTap(WeekWidgetNav.today, null);
  }
  if (action == 'calendar/prev') {
    return const WeekWidgetTap(WeekWidgetNav.prev, null);
  }
  if (action == 'calendar/next') {
    return const WeekWidgetTap(WeekWidgetNav.next, null);
  }
  if (action.startsWith('calendar/')) {
    final raw = action.substring('calendar/'.length);
    final day = WeekWidgetOptions.tryParseDayKey(raw);
    if (day != null) return WeekWidgetTap(WeekWidgetNav.day, day);
    return null;
  }
  return null;
}
