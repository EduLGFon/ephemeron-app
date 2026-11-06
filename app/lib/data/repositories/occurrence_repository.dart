import 'package:drift/drift.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/core/time/time.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/domain/recurrence/recurrence_rule.dart';
import 'package:ephemeron/features/calendar/presentation/google_calendar_colors.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// Materializes recurring and single events into `occurrence_cache`
// for a rolling window (visible month +/- 1 month per PLAN 5.3).
// UI reads only from this table via [watchDay].
//
// Split across `part` files using mixins-on-base so every public method
// stays declared on [OccurrenceRepository] (no extensions that would hide
// members from importers). See task_repository.dart for the same pattern.
part 'occurrence_repository/events.dart';

part 'occurrence_repository/tasks.dart';

part 'occurrence_repository/queries.dart';

/// Base holding database access and parsing helpers shared by all parts.
class _OccurrenceRepositoryBase {
  _OccurrenceRepositoryBase(this._db);

  final AppDatabase _db;

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
  JoinedSelectStatement _pendingDeletes() {
    return _db.selectOnly(_db.pendingOperations)
      ..addColumns([_db.pendingOperations.entityId])
      ..where(
        _db.pendingOperations.entity.isIn(const ['event', 'task']) &
            _db.pendingOperations.op.equals('delete'),
      );
  }
}

class OccurrenceRepository extends _OccurrenceRepositoryBase
    with _EventCacheOps, _TaskCacheOps, _CacheQueryOps {
  OccurrenceRepository(super._db) {
    tzdata.initializeTimeZones();
  }

  static const int instanceCap = 1000;
}
