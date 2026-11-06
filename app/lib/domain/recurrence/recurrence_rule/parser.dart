part of '../recurrence_rule.dart';

bool _tzReady = false;

void _ensureTz() {
  if (_tzReady) return;
  tzdata.initializeTimeZones();
  _tzReady = true;
}

/// IANA lookup that never throws: unknown abbreviations (for example
/// `DateTime.now().timeZoneName` values like "-03") fall back to UTC
/// instead of crashing occurrence expansion.
tz.Location _safeLocation(String? tzId) {
  if (tzId == null || tzId == 'UTC') return tz.UTC;
  try {
    return tz.getLocation(tzId);
  } catch (_) {
    return tz.UTC;
  }
}

DateTime _parseUtc(String v) {
  final s = v.replaceAll('Z', '');
  if (s.length == 8) {
    return DateTime.utc(
      int.parse(s.substring(0, 4)),
      int.parse(s.substring(4, 6)),
      int.parse(s.substring(6, 8)),
    );
  }
  return DateTime.utc(
    int.parse(s.substring(0, 4)),
    int.parse(s.substring(4, 6)),
    int.parse(s.substring(6, 8)),
    int.parse(s.substring(9, 11)),
    int.parse(s.substring(11, 13)),
    s.length >= 15 ? int.parse(s.substring(13, 15)) : 0,
  );
}
