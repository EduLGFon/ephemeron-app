import 'package:device_calendar_plus/device_calendar_plus.dart' as dev_cal;
import '../domain/calendar_event.dart';

class DeviceCalendarRepository {
  DeviceCalendarRepository();

  final _deviceCalendar = dev_cal.DeviceCalendar();

  Future<bool> hasPermission() async {
    final status = await _deviceCalendar.hasPermissions();
    return status == dev_cal.CalendarPermissionStatus.granted;
  }

  Future<bool> requestPermission() async {
    final status = await _deviceCalendar.requestPermissions();
    return status == dev_cal.CalendarPermissionStatus.granted;
  }

  Future<List<dev_cal.Calendar>> retrieveCalendars() async {
    final hasPerm = await hasPermission();
    if (!hasPerm) {
      final requested = await requestPermission();
      if (!requested) return const [];
    }
    try {
      return await _deviceCalendar.listCalendars();
    } catch (_) {
      return const [];
    }
  }

  Future<List<CalendarEvent>> retrieveEvents({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required Set<String> enabledCalendarIds,
  }) async {
    if (enabledCalendarIds.isEmpty) return const [];
    
    final hasPerm = await hasPermission();
    if (!hasPerm) return const [];

    try {
      final calendars = await _deviceCalendar.listCalendars();
      final colorMap = <String, String>{};
      for (final cal in calendars) {
        if (cal.colorHex != null) {
          colorMap[cal.id] = cal.colorHex!;
        }
      }

      final eventsResult = await _deviceCalendar.listEvents(
        rangeStart,
        rangeEnd,
        calendarIds: enabledCalendarIds.toList(),
      );

      final List<CalendarEvent> mappedEvents = [];
      for (final event in eventsResult) {
        final calColor = colorMap[event.calendarId] ?? '#6C63FF';
        mappedEvents.add(
          CalendarEvent(
            id: 'device:${event.calendarId}:${event.instanceId}',
            calendarId: event.calendarId,
            title: event.title.trim().isEmpty ? '(No title)' : event.title,
            description: event.description,
            location: event.location,
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            colorId: 'device:$calColor',
            attendees: event.attendees
                    ?.map((a) => a.emailAddress ?? '')
                    .where((e) => e.isNotEmpty)
                    .toList() ??
                const [],
          ),
        );
      }
      return mappedEvents;
    } catch (_) {
      return const [];
    }
  }

  Future<void> createEvent(CalendarEvent event) async {
    final hasPerm = await hasPermission();
    if (!hasPerm) return;

    await _deviceCalendar.createEvent(
      calendarId: event.calendarId,
      title: event.title,
      startDate: event.start,
      endDate: event.end,
      isAllDay: event.isAllDay,
      description: event.description,
      location: event.location,
    );
  }

  Future<void> deleteEvent(String calendarId, String eventId) async {
    final hasPerm = await hasPermission();
    if (!hasPerm) return;

    await _deviceCalendar.deleteEvent(
      eventId: eventId,
    );
  }
}
