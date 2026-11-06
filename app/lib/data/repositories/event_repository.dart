// Event and calendar repository: CRUD, recurrence scope ops (PLAN 5.4),
// outbox rows, occurrence-cache invalidation.
// UI reads occurrences via OccurrenceRepository streams.
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/core/search/sanitize.dart';
import 'package:ephemeron/core/time/time.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/outbox_helper.dart';
import 'package:ephemeron/data/repositories/occurrence_repository.dart';
import 'package:ephemeron/domain/sources/source_move.dart';

part 'event_repository/helpers.dart';
part 'event_repository/move.dart';
part 'event_repository/calendars.dart';
part 'event_repository/attendees.dart';
part 'event_repository/events.dart';
part 'event_repository/queries.dart';
part 'event_repository/occurrence_ops.dart';

enum EditScope { single, following, all }

class EventRepository {
  EventRepository(this._db, this._occ);

  final AppDatabase _db;
  final OccurrenceRepository _occ;

  /// Pure self-resolution over already-loaded rows (see [selfAttendeeOf]).
  static EventAttendee? resolveSelf(
    List<EventAttendee> atts,
    List<String> accountEmails,
  ) {
    if (atts.isEmpty) return null;
    final flagged = atts.where((a) => a.isSelf).firstOrNull;
    if (flagged != null) return flagged;
    if (accountEmails.isNotEmpty) {
      final known = {for (final e in accountEmails) e.toLowerCase()};
      return atts
          .where((a) => known.contains(a.email.toLowerCase()))
          .firstOrNull;
    }
    final guest = atts.where((a) => !a.isOrganizer).firstOrNull;
    return guest ?? atts.first;
  }
}
