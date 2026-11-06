part of '../event_repository.dart';

extension EventRepositoryHelpers on EventRepository {
  Future<void> _enqueue(String entityId, String op, {String? payload}) =>
      enqueueOutbox(
        _db,
        entity: 'event',
        entityId: entityId,
        op: op,
        payload: payload,
      );

  Future<void> _enqueueRemoteDelete({
    required String eventId,
    required String calendarRemoteId,
    required String eventRemoteId,
    required String account,
  }) {
    return enqueueOutbox(
      _db,
      entity: 'event_remote',
      entityId: eventId,
      op: 'delete',
      payload: jsonEncode({
        'account': account,
        'calendarRemoteId': calendarRemoteId,
        'eventRemoteId': eventRemoteId,
      }),
    );
  }

  /// Next calendar day for a `YYYY-MM-DD` string.
  String _nextDate(String date) {
    final parts = date.split('-');
    if (parts.length != 3) return date;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return date;
    return _dateOf(DateTime.utc(year, month, day + 1).millisecondsSinceEpoch);
  }

  Future<String?> _accountOfCalendar(String calendarId) async {
    return (await _calendar(calendarId))?.googleAccount;
  }

  Future<Calendar?> _calendar(String calendarId) {
    return (_db.select(
      _db.calendars,
    )..where((c) => c.id.equals(calendarId))).getSingleOrNull();
  }

  Future<Event> _master(String id) async {
    return (dbSelect()..where((e) => e.id.equals(id))).getSingle();
  }

  SimpleSelectStatement<$EventsTable, Event> dbSelect() =>
      _db.select(_db.events);

  Future<void> _writeEventSource(
    String eventId,
    String calendarId,
    String? account, {
    required bool dirty,
    required bool clearRemote,
    required int now,
  }) {
    return (_db.update(_db.events)..where((e) => e.id.equals(eventId))).write(
      EventsCompanion(
        calendarId: Value(calendarId),
        googleAccount: Value(account),
        remoteId: clearRemote ? const Value(null) : const Value.absent(),
        remoteEtag: clearRemote ? const Value(null) : const Value.absent(),
        dirty: Value(dirty),
        updatedAt: Value(now),
      ),
    );
  }

  String _dateOf(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  String _untilUtc(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    String p(int v, int w) => v.toString().padLeft(w, '0');
    return '${p(d.year, 4)}${p(d.month, 2)}${p(d.day, 2)}T${p(d.hour, 2)}${p(d.minute, 2)}${p(d.second, 2)}Z';
  }

  String _stripCount(String rrule) {
    final parts = rrule
        .split(';')
        .where((p) => !p.toUpperCase().startsWith('COUNT='));
    return parts.join(';');
  }
}
