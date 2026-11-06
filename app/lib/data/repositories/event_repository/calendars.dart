part of '../event_repository.dart';

extension EventRepositoryCalendars on EventRepository {
  // Calendars.

  Stream<List<Calendar>> watchCalendars() {
    return (_db.select(
      _db.calendars,
    )..orderBy([(c) => OrderingTerm.asc(c.name)])).watch();
  }

  Future<String> createCalendar(
    String name, {
    String source = 'device',
    String? color,
  }) async {
    final id = newId();
    final now = nowMs();
    await _db
        .into(_db.calendars)
        .insert(
          CalendarsCompanion.insert(
            id: id,
            name: name,
            source: Value(source),
            color: Value(color),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> setCalendarEnabled(String id, bool enabled) async {
    await (_db.update(_db.calendars)..where((c) => c.id.equals(id))).write(
      CalendarsCompanion(enabled: Value(enabled), updatedAt: Value(nowMs())),
    );
  }
}
