part of '../occurrence_repository.dart';

OccurrenceCacheCompanion _row(
  String eventId,
  int startMs,
  int endMs,
  String dayKeyValue, {
  String? title,
  String? colorId,
  String sourceType = 'event',
}) {
  return OccurrenceCacheCompanion.insert(
    id: newId(),
    eventId: eventId,
    title: Value(title),
    colorId: Value(colorId),
    startUtc: startMs,
    endUtc: endMs,
    dayKey: dayKeyValue,
    sourceType: Value(sourceType),
  );
}

String _dayKey(int utcMs, String? tzId) {
  if (tzId == null) {
    // Floating local event: group by device-local date so the timeline
    // (which renders local wall time) shows it on the expected day.
    return dateKey(DateTime.fromMillisecondsSinceEpoch(utcMs));
  }
  if (tzId == 'UTC') {
    return dateKey(DateTime.fromMillisecondsSinceEpoch(utcMs, isUtc: true));
  }
  try {
    final loc = tz.getLocation(tzId);
    return dateKey(
      tz.TZDateTime.from(
        DateTime.fromMillisecondsSinceEpoch(utcMs, isUtc: true),
        loc,
      ),
    );
  } catch (_) {
    // Non-IANA abbreviations (e.g. "-03") must not crash the rebuild.
    return dateKey(DateTime.fromMillisecondsSinceEpoch(utcMs));
  }
}

DateTime _parseDate(String ymd) {
  final p = ymd.split('-');
  return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// Event or task ids queued for deletion.
JoinedSelectStatement _pendingDeletes(AppDatabase db) {
  return db.selectOnly(db.pendingOperations)
    ..addColumns([db.pendingOperations.entityId])
    ..where(
      db.pendingOperations.entity.isIn(const ['event', 'task']) &
          db.pendingOperations.op.equals('delete'),
    );
}
