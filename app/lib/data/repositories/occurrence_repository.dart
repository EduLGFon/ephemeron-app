import 'package:drift/drift.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/core/time/time.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/domain/recurrence/recurrence_rule.dart';
import 'package:ephemeron/features/calendar/presentation/google_calendar_colors.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

part 'occurrence_repository/helpers.dart';
part 'occurrence_repository/window_rebuild.dart';
part 'occurrence_repository/event_expansion.dart';
part 'occurrence_repository/task_expansion.dart';
part 'occurrence_repository/queries.dart';

// Materializes recurring and single events into `occurrence_cache`
// for a rolling window (visible month +/- 1 month per PLAN 5.3).
// UI reads only from this table via [watchDay].
class OccurrenceRepository {
  OccurrenceRepository(this._db) {
    tzdata.initializeTimeZones();
  }

  final AppDatabase _db;

  static const int instanceCap = 1000;
}
