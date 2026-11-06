part of '../microsoft_graph_models.dart';

/// Microsoft dateTimeTimeZone value. With the UTC Prefer header, [timeZone]
/// is "UTC" and [utc] is populated.
class MsDateTimeTimeZone {
  const MsDateTimeTimeZone({required this.dateTime, required this.timeZone});

  final String dateTime;
  final String timeZone;

  bool get isUtc =>
      timeZone.toUpperCase() == 'UTC' || timeZone.toUpperCase() == 'ETC/UTC';

  DateTime? get utc {
    if (dateTime.isEmpty) return null;
    var s = dateTime;
    if (isUtc && !s.endsWith('Z') && !s.contains('+')) {
      s = '${s}Z';
    }
    return DateTime.tryParse(s)?.toUtc();
  }

  DateTime? get local => utc?.toLocal();

  factory MsDateTimeTimeZone.fromMap(Map<String, dynamic> m) {
    return MsDateTimeTimeZone(
      dateTime: (m['dateTime'] as String?) ?? '',
      timeZone: (m['timeZone'] as String?) ?? 'UTC',
    );
  }
}

class MsLocation {
  const MsLocation({this.displayName, this.locationType});

  final String? displayName;
  final String? locationType;

  factory MsLocation.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const MsLocation();
    return MsLocation(
      displayName: m['displayName'] as String?,
      locationType: m['locationType'] as String?,
    );
  }
}
