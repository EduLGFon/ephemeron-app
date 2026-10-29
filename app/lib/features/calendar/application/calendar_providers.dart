// Calendar providers: repositories, visible window, occurrence streams.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/db_provider.dart';
import '../../../data/drift/app_database.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../data/repositories/occurrence_repository.dart';
import '../application/calendar_state.dart';

final occurrenceRepositoryProvider = Provider<OccurrenceRepository>((ref) {
  return OccurrenceRepository(ref.watch(appDatabaseProvider));
});

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(occurrenceRepositoryProvider),
  );
});

final calendarsProvider = StreamProvider<List<Calendar>>((ref) {
  return ref.watch(eventRepositoryProvider).watchCalendars();
});

final calendarStateProvider = NotifierProvider<CalendarState, CalendarWindow>(
  CalendarState.new,
);

final windowOccurrencesProvider =
    StreamProvider.family<List<OccurrenceCacheData>, CalendarWindow>((
      ref,
      window,
    ) {
      return ref
          .watch(occurrenceRepositoryProvider)
          .watchWindow(window.fromUtc, window.toUtc);
    });
