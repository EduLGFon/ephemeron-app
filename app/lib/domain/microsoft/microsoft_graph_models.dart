// Typed Microsoft Graph domain models. No dynamic escape hatches at the
// boundary; parsing happens in factories here.
class MsEmailAddress {
  const MsEmailAddress({this.name, this.address});

  final String? name;
  final String? address;

  factory MsEmailAddress.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const MsEmailAddress();
    return MsEmailAddress(
      name: m['name'] as String?,
      address: m['address'] as String?,
    );
  }
}

class MsIdentity {
  const MsIdentity({
    required this.id,
    this.displayName,
    this.mail,
    this.userPrincipalName,
  });

  final String id;
  final String? displayName;
  final String? mail;
  final String? userPrincipalName;

  factory MsIdentity.fromMap(Map<String, dynamic> m) {
    return MsIdentity(
      id: (m['id'] as String?) ?? '',
      displayName: m['displayName'] as String?,
      mail: m['mail'] as String?,
      userPrincipalName: m['userPrincipalName'] as String?,
    );
  }
}

class MsCalendar {
  const MsCalendar({
    required this.id,
    required this.name,
    this.color,
    this.hexColor,
    this.isDefaultCalendar = false,
    this.canEdit = false,
    this.owner,
  });

  final String id;
  final String name;
  final String? color;
  final String? hexColor;
  final bool isDefaultCalendar;
  final bool canEdit;
  final MsEmailAddress? owner;

  factory MsCalendar.fromMap(Map<String, dynamic> m) {
    return MsCalendar(
      id: (m['id'] as String?) ?? '',
      name: (m['name'] as String?) ?? '',
      color: m['color'] as String?,
      hexColor: m['hexColor'] as String?,
      isDefaultCalendar: m['isDefaultCalendar'] as bool? ?? false,
      canEdit: m['canEdit'] as bool? ?? false,
      owner: m['owner'] is Map<String, dynamic>
          ? MsEmailAddress.fromMap(m['owner'] as Map<String, dynamic>)
          : null,
    );
  }
}

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

class MsEvent {
  const MsEvent({
    required this.id,
    this.subject,
    this.bodyPreview,
    this.start,
    this.end,
    this.isAllDay = false,
    this.location,
    this.showAs,
    this.isCancelled = false,
    this.seriesMasterId,
    this.type,
    this.recurrence,
    this.onlineMeetingUrl,
    this.attendees = const [],
    this.organizer,
    this.lastModifiedDateTime,
  });

  final String id;
  final String? subject;
  final String? bodyPreview;
  final MsDateTimeTimeZone? start;
  final MsDateTimeTimeZone? end;
  final bool isAllDay;
  final MsLocation? location;
  final String? showAs;
  final bool isCancelled;
  final String? seriesMasterId;
  final String? type;
  final MsRecurrence? recurrence;
  final String? onlineMeetingUrl;
  final List<MsAttendee> attendees;
  final MsAttendee? organizer;
  final DateTime? lastModifiedDateTime;

  factory MsEvent.fromMap(Map<String, dynamic> m) {
    DateTime? lastMod;
    final rawLast = m['lastModifiedDateTime'];
    if (rawLast is String) lastMod = DateTime.tryParse(rawLast)?.toUtc();
    return MsEvent(
      id: (m['id'] as String?) ?? '',
      subject: m['subject'] as String?,
      bodyPreview: m['bodyPreview'] as String?,
      start: m['start'] is Map<String, dynamic>
          ? MsDateTimeTimeZone.fromMap(m['start'] as Map<String, dynamic>)
          : null,
      end: m['end'] is Map<String, dynamic>
          ? MsDateTimeTimeZone.fromMap(m['end'] as Map<String, dynamic>)
          : null,
      isAllDay: m['isAllDay'] as bool? ?? false,
      location: m['location'] is Map<String, dynamic>
          ? MsLocation.fromMap(m['location'] as Map<String, dynamic>)
          : null,
      showAs: m['showAs'] as String?,
      isCancelled: m['isCancelled'] as bool? ?? false,
      seriesMasterId: m['seriesMasterId'] as String?,
      type: m['type'] as String?,
      recurrence: m['recurrence'] is Map<String, dynamic>
          ? MsRecurrence.fromMap(m['recurrence'] as Map<String, dynamic>)
          : null,
      onlineMeetingUrl: m['onlineMeetingUrl'] as String?,
      attendees: m['attendees'] is List
          ? (m['attendees'] as List)
                .whereType<Map<String, dynamic>>()
                .map(MsAttendee.fromMap)
                .toList()
          : const [],
      organizer: m['organizer'] is Map<String, dynamic>
          ? MsAttendee.fromMap(m['organizer'] as Map<String, dynamic>)
          : null,
      lastModifiedDateTime: lastMod,
    );
  }
}

class MsTodoList {
  const MsTodoList({
    required this.id,
    required this.displayName,
    this.wellknownListName,
  });

  final String id;
  final String displayName;
  final String? wellknownListName;

  factory MsTodoList.fromMap(Map<String, dynamic> m) {
    return MsTodoList(
      id: (m['id'] as String?) ?? '',
      displayName: (m['displayName'] as String?) ?? '',
      wellknownListName: m['wellknownListName'] as String?,
    );
  }
}

DateTime? _parseDateTime(dynamic v) {
  if (v == null) return null;
  if (v is String) return DateTime.tryParse(v)?.toUtc();
  if (v is Map<String, dynamic>) {
    return MsDateTimeTimeZone.fromMap(v).utc;
  }
  return null;
}

String? _bodyContent(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  if (v is Map<String, dynamic>) {
    return v['content'] as String?;
  }
  return null;
}

class MsTodoTask {
  const MsTodoTask({
    required this.id,
    required this.title,
    this.body,
    this.importance,
    this.status,
    this.dueDateTime,
    this.completedDateTime,
    this.createdDateTime,
    this.lastModifiedDateTime,
  });

  final String id;
  final String title;
  final String? body;
  final String? importance;
  final String? status;
  final MsDateTimeTimeZone? dueDateTime;
  final MsDateTimeTimeZone? completedDateTime;
  final DateTime? createdDateTime;
  final DateTime? lastModifiedDateTime;

  factory MsTodoTask.fromMap(Map<String, dynamic> m) {
    MsDateTimeTimeZone? due;
    final dueRaw = m['dueDateTime'];
    if (dueRaw is Map<String, dynamic>) {
      due = MsDateTimeTimeZone.fromMap(dueRaw);
    }
    MsDateTimeTimeZone? completed;
    final compRaw = m['completedDateTime'];
    if (compRaw is Map<String, dynamic>) {
      completed = MsDateTimeTimeZone.fromMap(compRaw);
    }
    return MsTodoTask(
      id: (m['id'] as String?) ?? '',
      title: (m['title'] as String?) ?? '',
      body: _bodyContent(m['body']),
      importance: m['importance'] as String?,
      status: m['status'] as String?,
      dueDateTime: due,
      completedDateTime: completed,
      createdDateTime: _parseDateTime(m['createdDateTime']),
      lastModifiedDateTime: _parseDateTime(m['lastModifiedDateTime']),
    );
  }
}
