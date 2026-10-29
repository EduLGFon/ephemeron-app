// Google Calendar/Tasks <-> Drift mappers. Local-only fields are never
// overwritten by remote data; last-writer-wins applies to shared fields.
import 'package:drift/drift.dart';

import '../../data/drift/app_database.dart';

class MappedEvent {
  MappedEvent({required this.companion, required this.remoteEtag});
  final EventsCompanion companion;
  final String? remoteEtag;
}

MappedEvent eventFromGoogle(
  Map<String, dynamic> g,
  String calendarId,
  String localId,
) {
  final start = g['start'] as Map? ?? {};
  final end = g['end'] as Map? ?? {};
  final isAllDay = start['date'] != null;
  int? startUtc;
  int? endUtc;
  String? startDate;
  String? endDate;
  if (isAllDay) {
    startDate = start['date'] as String?;
    endDate = end['date'] as String?;
  } else {
    final s = start['dateTime'] as String?;
    final e = end['dateTime'] as String?;
    if (s != null) {
      startUtc = DateTime.parse(s).toUtc().millisecondsSinceEpoch;
    }
    if (e != null) {
      endUtc = DateTime.parse(e).toUtc().millisecondsSinceEpoch;
    }
  }
  String? notes = g['description'] as String?;
  if (notes != null && notes.length > 8000) {
    // Remainder stays local-only until notes overflow lands (Phase 7).
    notes = notes.substring(0, 8000);
  }
  String? rrule;
  final rec = g['recurrence'] as List?;
  if (rec != null && rec.isNotEmpty) {
    rrule = (rec.first as String).replaceFirst('RRULE:', '');
  }
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  return MappedEvent(
    companion: EventsCompanion(
      id: Value(localId),
      calendarId: Value(calendarId),
      title: Value((g['summary'] as String?) ?? ''),
      notes: Value(notes),
      location: Value(g['location'] as String?),
      startUtc: Value(startUtc),
      endUtc: Value(endUtc),
      startDate: Value(startDate),
      endDate: Value(endDate),
      isAllDay: Value(isAllDay),
      tzId: Value(start['timeZone'] as String?),
      endTzId: Value(end['timeZone'] as String?),
      rrule: Value(rrule),
      status: Value((g['status'] as String?) ?? 'confirmed'),
      transparency: Value(g['transparency'] as String?),
      visibility: Value(g['visibility'] as String?),
      remoteId: Value(g['id'] as String?),
      remoteEtag: Value(g['etag'] as String?),
      dirty: const Value(false),
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
    remoteEtag: g['etag'] as String?,
  );
}

Map<String, dynamic> eventToGoogle(Event e) {
  final body = <String, dynamic>{
    'summary': e.title,
    if (e.notes != null) 'description': e.notes,
    if (e.location != null) 'location': e.location,
    'status': e.status,
    if (e.transparency != null) 'transparency': e.transparency,
    if (e.isAllDay)
      'start': {'date': e.startDate}
    else
      'start': {
        'dateTime': e.startUtc == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                e.startUtc!,
                isUtc: true,
              ).toIso8601String(),
        if (e.tzId != null) 'timeZone': e.tzId,
      },
    if (e.isAllDay)
      'end': {'date': e.endDate ?? e.startDate}
    else
      'end': {
        'dateTime': e.endUtc == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                e.endUtc!,
                isUtc: true,
              ).toIso8601String(),
        if ((e.endTzId ?? e.tzId) != null) 'timeZone': e.endTzId ?? e.tzId,
      },
    if (e.rrule != null && e.rrule!.isNotEmpty)
      'recurrence': ['RRULE:${e.rrule}'],
  };
  return body;
}

class MappedTask {
  MappedTask({required this.companion, required this.remoteEtag});
  final TasksCompanion companion;
  final String? remoteEtag;
}

MappedTask taskFromGoogle(
  Map<String, dynamic> g,
  String? listId,
  String localId,
) {
  String? dueDate;
  final due = g['due'] as String?;
  if (due != null) dueDate = due.substring(0, 10);
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  return MappedTask(
    companion: TasksCompanion(
      id: Value(localId),
      listId: Value(listId),
      title: Value((g['title'] as String?) ?? ''),
      notes: Value(g['notes'] as String?),
      dueDate: Value(dueDate),
      completedAt: g['status'] == 'completed'
          ? Value(
              DateTime.tryParse(
                    g['completed'] as String? ?? '',
                  )?.toUtc().millisecondsSinceEpoch ??
                  now,
            )
          : const Value(null),
      deletedAt: (g['deleted'] == true) ? Value(now) : const Value(null),
      remoteId: Value(g['id'] as String?),
      remoteEtag: Value(g['etag'] as String?),
      dirty: const Value(false),
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
    remoteEtag: g['etag'] as String?,
  );
}

Map<String, dynamic> taskToGoogle(Task t) => {
  'title': t.title,
  if (t.notes != null) 'notes': t.notes,
  if (t.dueDate != null) 'due': '${t.dueDate}T00:00:00.000Z',
  if (t.completedAt != null)
    'status': 'completed'
  else if (t.deletedAt != null)
    'deleted': true,
};
