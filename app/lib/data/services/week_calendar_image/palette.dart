part of '../week_calendar_image.dart';

/// Resolved palette for one widget theme. Transparent paints no solid
/// background and uses light foreground colors so the grid stays readable
/// over launcher wallpaper.
class _WeekPalette {
  const _WeekPalette({
    required this.background,
    required this.line,
    required this.night,
    required this.text,
    required this.todayFill,
    required this.todayText,
    required this.nowLine,
  });

  final Color? background;
  final Color line;
  final Color night;
  final Color text;
  final Color todayFill;
  final Color todayText;
  final Color nowLine;

  static _WeekPalette of(WeekWidgetTheme theme) {
    switch (theme) {
      case WeekWidgetTheme.dark:
        return const _WeekPalette(
          background: Color(0xFF1B1B1D),
          line: Color(0xFF3A3A3E),
          night: Color(0xFF232326),
          text: Color(0xFFFFFFFF),
          todayFill: Color(0xFFFFFFFF),
          todayText: Color(0xFF000000),
          nowLine: Color(0xFFFF5252),
        );
      case WeekWidgetTheme.transparent:
        return const _WeekPalette(
          background: null,
          line: Color(0x99FFFFFF),
          night: Color(0x22000000),
          text: Color(0xFFFFFFFF),
          todayFill: Color(0xAAFFFFFF),
          todayText: Color(0xFF000000),
          nowLine: Color(0xFFFF5252),
        );
      case WeekWidgetTheme.light:
        return const _WeekPalette(
          background: Color(0xFFFFFFFF),
          line: Color(0xFFE2E2E2),
          night: Color(0xFFF7F7F7),
          text: Color(0xFF000000),
          todayFill: Color(0xFF000000),
          todayText: Color(0xFFFFFFFF),
          nowLine: Color(0xFFD50000),
        );
    }
  }
}
