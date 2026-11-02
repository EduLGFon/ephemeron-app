// Shared Google Calendar color palette (colorId -> Color). Single source
// of truth used by the editor and timeline views.
//
// Stored occurrence colors are either a palette id ('1'-'11') or a CSS hex
// ('#039be5') copied from the calendar's Google backgroundColor. Helpers
// below parse both and derive a stable per-calendar fallback so distinct
// calendars never collapse to one color.
import 'package:flutter/material.dart';

const Map<String, Color> googleCalendarColors = <String, Color>{
  '1': Color(0xFF7986CB),
  '2': Color(0xFF33B679),
  '3': Color(0xFF8E24AA),
  '4': Color(0xFFE67C73),
  '5': Color(0xFFF6BF26),
  '6': Color(0xFF3F51B5),
  '7': Color(0xFF039BE5),
  '8': Color(0xFF0B8043),
  '9': Color(0xFFD50000),
  '10': Color(0xFF303F9F),
  '11': Color(0xFF616161),
};

/// Parses '#rrggbb', '#aarrggbb', with or without '#'. Returns null when
/// the value is not a valid hex color.
Color? tryParseCssHex(String? raw) {
  if (raw == null) return null;
  var hex = raw.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length != 6 && hex.length != 8) return null;
  for (var i = 0; i < hex.length; i++) {
    final c = hex.codeUnitAt(i);
    final ok =
        (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102);
    if (!ok) return null;
  }
  final v = int.parse(hex, radix: 16);
  return hex.length == 6 ? Color(0xFF000000 | v) : Color(v);
}

/// Resolves a stored color (palette id or CSS hex) to a [Color].
Color googleCalendarColor(String id, {Color fallback = Colors.blue}) =>
    googleCalendarColors[id] ?? tryParseCssHex(id) ?? fallback;

/// Stable palette id ('1'-'11') derived from an arbitrary seed such as a
/// calendar or task-list id. Uses djb2 so it is stable across runs
/// (Dart's String.hashCode is not guaranteed stable).
String stablePaletteIdFor(String seed) {
  var hash = 5381;
  for (var i = 0; i < seed.length; i++) {
    hash = ((hash << 5) + hash + seed.codeUnitAt(i)) & 0xFFFFFFFF;
  }
  return '${(hash % 11) + 1}';
}

/// Effective stored color for an event occurrence: per-event override wins,
/// then the parent calendar color (hex or palette id), then a stable
/// per-calendar fallback so calendars without a synced color still differ.
String effectiveEventColor({
  required String? eventColorId,
  required String? calendarColor,
  required String calendarId,
}) {
  if (eventColorId != null && eventColorId.isNotEmpty) return eventColorId;
  if (calendarColor != null && calendarColor.isNotEmpty) return calendarColor;
  return stablePaletteIdFor('cal:$calendarId');
}

/// Effective stored color for a task occurrence: parent list color wins,
/// then a stable per-list fallback.
String effectiveTaskColor({required String? listColor, required String seed}) {
  if (listColor != null && listColor.isNotEmpty) return listColor;
  return stablePaletteIdFor('list:$seed');
}
