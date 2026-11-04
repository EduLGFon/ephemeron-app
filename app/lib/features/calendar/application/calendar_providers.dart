// Calendar providers: repositories, visible window, occurrence streams.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/db_provider.dart';
import '../../../data/drift/app_database.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../data/repositories/occurrence_repository.dart';
import '../../auth/application/auth_providers.dart';
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

final selfRsvpForEventProvider = FutureProvider.family<String?, String>((
  ref,
  eventId,
) async {
  final repo = ref.watch(eventRepositoryProvider);
  // Self is resolved by flag first, then by matching attendee email against
  // the signed-in accounts (rows synced before self flags existed).
  final accounts = ref.watch(googleAccountsProvider);
  final active = ref.watch(googleAccountProvider);
  final emails = active == null ? accounts : [active, ...accounts];
  final self = await repo.selfAttendeeOf(eventId, emails);
  final raw = self?.rsvp;
  // Google also returns needsAction/no response; those mean "no decision".
  if (raw == 'accepted' || raw == 'declined' || raw == 'tentative') {
    return raw;
  }
  return null;
});
