// Device calendar import: reads OS calendars/events via device_calendar_plus
// and copies them into a local app calendar. Degrades gracefully on platforms
// without native calendar access.
import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:ephemeron/data/repositories/event_repository.dart';

class DeviceCalendarInfo {
  const DeviceCalendarInfo({
    required this.id,
    required this.name,
    this.colorHex,
    this.readOnly = false,
  });
  final String id;
  final String name;
  final String? colorHex;
  final bool readOnly;
}

class DeviceCalendarImportService {
  DeviceCalendarImportService(this._repo);
  final EventRepository _repo;

  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<List<DeviceCalendarInfo>> listCalendars() async {
    if (!isSupported) return const [];
    try {
      final cals = await DeviceCalendar.instance.listCalendars();
      return cals
          .where((c) => !c.hidden)
          .map(
            (c) => DeviceCalendarInfo(
              id: c.id,
              name: c.name,
              colorHex: c.colorHex,
              readOnly: c.readOnly,
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<int> requestPermission() async {
    if (!isSupported) return 0;
    try {
      final status = await DeviceCalendar.instance.requestPermissions();
      if (status == CalendarPermissionStatus.granted ||
          status == CalendarPermissionStatus.writeOnly) {
        return 1;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  /// Imports events from [deviceCalendarId] into [targetCalendarId].
  /// Returns number of events imported.
  Future<int> importCalendar({
    required String deviceCalendarId,
    required String targetCalendarId,
    DateTime? from,
    DateTime? to,
  }) async {
    if (!isSupported) return 0;
    final now = DateTime.now();
    final start = from ?? now.subtract(const Duration(days: 30));
    final end = to ?? now.add(const Duration(days: 365));
    try {
      final events = await DeviceCalendar.instance.listEvents(
        start,
        end,
        calendarIds: [deviceCalendarId],
      );
      int count = 0;
      for (final e in events) {
        final title = (e.title.isEmpty) ? '(untitled)' : e.title;
        String id;
        if (e.isAllDay) {
          id = await _repo.createEvent(
            calendarId: targetCalendarId,
            title: title,
            startDate: _dateStr(e.startDate),
            endDate: _dateStr(e.endDate),
            allDay: true,
            location: e.location,
            notes: e.description,
            rrule: e.recurrenceRule?.rruleString,
          );
        } else {
          id = await _repo.createEvent(
            calendarId: targetCalendarId,
            title: title,
            startUtc: e.startDate,
            endUtc: e.endDate,
            allDay: false,
            tzId: e.timeZone,
            location: e.location,
            notes: e.description,
            rrule: e.recurrenceRule?.rruleString,
          );
        }
        final atts = e.attendees;
        if (atts != null) {
          final emails = atts
              .map((a) => a.emailAddress)
              .whereType<String>()
              .toList();
          if (emails.isNotEmpty) {
            await _repo.setAttendees(id, emails);
          }
        }
        count++;
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  String _dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
