part of '../microsoft_graph_models.dart';

class MsAttendeeStatus {
  const MsAttendeeStatus({this.response, this.time});

  final String? response;
  final DateTime? time;

  factory MsAttendeeStatus.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const MsAttendeeStatus();
    DateTime? t;
    final raw = m['time'];
    if (raw is String) t = DateTime.tryParse(raw)?.toUtc();
    return MsAttendeeStatus(response: m['response'] as String?, time: t);
  }
}

class MsAttendee {
  const MsAttendee({this.emailAddress, this.type, this.status});

  final MsEmailAddress? emailAddress;
  final String? type;
  final MsAttendeeStatus? status;

  String? get response => status?.response;

  factory MsAttendee.fromMap(Map<String, dynamic> m) {
    return MsAttendee(
      emailAddress: m['emailAddress'] is Map<String, dynamic>
          ? MsEmailAddress.fromMap(m['emailAddress'] as Map<String, dynamic>)
          : null,
      type: m['type'] as String?,
      status: m['status'] is Map<String, dynamic>
          ? MsAttendeeStatus.fromMap(m['status'] as Map<String, dynamic>)
          : null,
    );
  }
}

class MsRecurrencePattern {
  const MsRecurrencePattern({
    this.type,
    this.interval,
    this.daysOfWeek = const [],
    this.firstDayOfWeek,
    this.index,
    this.dayOfMonth,
    this.month,
  });

  final String? type;
  final int? interval;
  final List<String> daysOfWeek;
  final String? firstDayOfWeek;
  final String? index;
  final int? dayOfMonth;
  final String? month;

  factory MsRecurrencePattern.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const MsRecurrencePattern();
    final days = m['daysOfWeek'];
    return MsRecurrencePattern(
      type: m['type'] as String?,
      interval: m['interval'] as int?,
      daysOfWeek: days is List ? days.whereType<String>().toList() : const [],
      firstDayOfWeek: m['firstDayOfWeek'] as String?,
      index: m['index'] as String?,
      dayOfMonth: m['dayOfMonth'] as int?,
      month: m['month'] as String?,
    );
  }
}

class MsRecurrenceRange {
  const MsRecurrenceRange({
    this.type,
    this.startDate,
    this.endDate,
    this.numberOfOccurrences,
  });

  final String? type;
  final String? startDate;
  final String? endDate;
  final int? numberOfOccurrences;

  factory MsRecurrenceRange.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const MsRecurrenceRange();
    return MsRecurrenceRange(
      type: m['type'] as String?,
      startDate: m['startDate'] as String?,
      endDate: m['endDate'] as String?,
      numberOfOccurrences: m['numberOfOccurrences'] as int?,
    );
  }
}

class MsRecurrence {
  const MsRecurrence({this.pattern, this.range});

  final MsRecurrencePattern? pattern;
  final MsRecurrenceRange? range;

  factory MsRecurrence.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const MsRecurrence();
    return MsRecurrence(
      pattern: m['pattern'] is Map<String, dynamic>
          ? MsRecurrencePattern.fromMap(m['pattern'] as Map<String, dynamic>)
          : null,
      range: m['range'] is Map<String, dynamic>
          ? MsRecurrenceRange.fromMap(m['range'] as Map<String, dynamic>)
          : null,
    );
  }
}
