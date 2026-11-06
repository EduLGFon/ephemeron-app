part of '../microsoft_graph_models.dart';

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
