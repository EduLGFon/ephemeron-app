# Habits on the calendar

## Problem

Habits were only visible on the Habits screen. Users could not see which habits
were scheduled for a given day while planning in the calendar, and logging a
habit required leaving the calendar. This change surfaces scheduled habits in the
timeline, month grid, and agenda, and makes logging a single tap.

## Schedule rules

`isHabitScheduled(HabitSpec spec, DateTime day)` in
`app/lib/domain/habits/streaks.dart` is the single scheduling predicate.

- `daily`: every day.
- `weekdays`: the day's weekday bit is set in `weekdaysMask` (Monday is bit 0).
- `interval`: every `intervalDays` days counted from `startDate`. If
  `intervalDays` is missing or below 1, the habit behaves as daily.
- `weekly`: available every day so the user can log any day toward the weekly
  target.
- All frequencies hide days before `startDate` when it is set.

Streaks use the same predicate, so the calendar and streak engine cannot drift
apart.

## Marker behavior

`HabitCalendarMarker` is the shared compact widget.

- Timeline day/multi-day: scheduled habits appear in the all-day strip with the
  habit name. The strip is shown when there are habits even if there are no
  all-day events.
- Month: habit markers occupy the same per-day slots as events. Events and
  habits are combined before slot calculation, so the `+N more` count stays
  correct and the cell cannot overflow.
- Agenda and month selected-day list: habit rows appear above events for each
  day. A day with only habits is not treated as empty.

## One-tap logging

- Tap a marker: toggles done for that day. If the day was not done it calls
  `logDone`; if it was done it sets done to false through `setDone`. Optimistic
  updates come from the existing Drift stream.
- Long-press a marker: opens an action sheet with Skip/Unskip and Open habits.

## Performance

- `HabitRepository.watchCalendarEntries(fromKey, toKey)` is one reactive Drift
  query over the requested date-key range. It reads `habits` and `habit_logs`,
  generates the day range in SQL, and filters scheduling in Dart, so there is no
  per-day N+1 query.
- `calendarHabitEntriesProvider` keys that stream to the existing calendar cache
  range, so timeline, month, and agenda share one subscription.
- No schema change, no new package, no timers, no background polling, and no
  change to battery behavior.

## Compatibility

- Calendar habit data is read-only from existing tables; no columns or
  migrations change.
- Archived and soft-deleted habits are excluded.
- Widgets degrade to no markers when the habit stream is loading or empty.
- Works on all supported platforms because it uses the same Drift and Flutter
  widgets as the rest of the calendar.

## Verification

- Domain scheduling cases: daily, weekdays, interval anchored on the start date,
  future start-date exclusion, weekly availability.
- Repository cases: range stream shape, done/skip state, archive exclusion, and
  toggle behavior.
- Widget case: tapping a month habit marker writes a done log for the day.
- `dart format` on changed files, `flutter analyze`, and `flutter test`.
