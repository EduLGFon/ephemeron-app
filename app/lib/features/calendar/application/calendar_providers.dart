// Calendar providers: repositories, visible window, occurrence streams.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/db_provider.dart';
import '../../../core/time/time.dart';
import '../../../data/drift/app_database.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../data/repositories/occurrence_repository.dart';
import '../../../domain/habits/habit_calendar_entry.dart';
import '../../../domain/sources/source_label.dart';
import '../../auth/application/auth_providers.dart';
import '../../habits/application/habits_providers.dart';
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

/// Cache range currently materialized for the visible calendar.
///
/// Keeps the previous range while it still covers the visible days, so day
/// and week swipes within the swipe buffer do not resubscribe occurrence
/// streams or trigger a rebuild.
class CalendarCacheRange extends Notifier<CalendarRange> {
  @override
  CalendarRange build() {
    final initial = ref.read(calendarStateProvider);
    ref.listen<CalendarWindow>(calendarStateProvider, (_, next) {
      if (!state.covers(next.visibleRange)) {
        state = next.cacheRange;
      }
    });
    return initial.cacheRange;
  }
}

final calendarCacheRangeProvider =
    NotifierProvider<CalendarCacheRange, CalendarRange>(CalendarCacheRange.new);

/// True while [OccurrenceRepository.rebuildWindow] is running.
class CalendarCacheBuilding extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final calendarCacheBuildingProvider =
    NotifierProvider<CalendarCacheBuilding, bool>(CalendarCacheBuilding.new);

final windowOccurrencesProvider =
    StreamProvider.family<List<OccurrenceCacheData>, CalendarRange>((
      ref,
      range,
    ) {
      return ref
          .watch(occurrenceRepositoryProvider)
          .watchWindow(range.fromUtc, range.toUtc);
    });

/// Scheduled habits with their log state for the materialized calendar range.
final calendarHabitEntriesProvider = StreamProvider<List<HabitCalendarEntry>>((
  ref,
) {
  final range = ref.watch(calendarCacheRangeProvider);
  final fromKey = dateKey(range.fromUtc);
  final toKey = dateKey(range.toUtc.subtract(const Duration(milliseconds: 1)));
  return ref
      .watch(habitRepositoryProvider)
      .watchCalendarEntries(fromKey, toKey);
});

/// Display source for an event occurrence. Loaded once per cache range so
/// timeline, agenda and month views can show labels without per-row queries.
class OccurrenceSource {
  const OccurrenceSource({
    required this.calendarId,
    required this.label,
    this.calendarName,
    this.account,
    this.isLocal = false,
  });

  final String calendarId;
  final String label;
  final String? calendarName;
  final String? account;
  final bool isLocal;
}

final occurrenceSourceMapProvider =
    FutureProvider<Map<String, OccurrenceSource>>((ref) async {
      final range = ref.watch(calendarCacheRangeProvider);
      final occurrences = await ref.watch(
        windowOccurrencesProvider(range).future,
      );
      final eventIds = {for (final o in occurrences) o.eventId};
      if (eventIds.isEmpty) return const {};
      final db = ref.watch(appDatabaseProvider);
      final ids = eventIds.toList();
      final events = <Event>[];
      // Keep each IN clause below SQLite's bind-variable limit.
      for (var i = 0; i < ids.length; i += 500) {
        final chunk = ids.sublist(
          i,
          i + 500 > ids.length ? ids.length : i + 500,
        );
        events.addAll(
          await (db.select(db.events)..where((e) => e.id.isIn(chunk))).get(),
        );
      }
      final calendars = await (db.select(db.calendars)).get();
      final calendarById = {for (final c in calendars) c.id: c};
      final out = <String, OccurrenceSource>{};
      for (final event in events) {
        final calendar = calendarById[event.calendarId];
        final isLocal =
            calendar == null ||
            (calendar.source != 'google' && calendar.source != 'microsoft');
        final account = accountForSource(
          googleAccount: event.googleAccount ?? calendar?.googleAccount,
          microsoftAccount:
              event.microsoftAccount ?? calendar?.microsoftAccount,
        );
        final name = calendar?.name;
        out[event.id] = OccurrenceSource(
          calendarId: event.calendarId,
          label:
              sourceLabel(name: name, account: account, isLocal: isLocal) ??
              'Source',
          calendarName: name,
          account: account,
          isLocal: isLocal,
        );
      }
      return out;
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
