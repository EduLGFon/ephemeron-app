# PROGRESS

## Phase 1 - Foundation
See docs/phase-1.md. Status: done (acceptance met; TODO.md lists env limits).

## Phase 2 - Recurrence and time core
Checklist:
- [x] RRULE parser (pure Dart): FREQ DAILY/WEEKLY/MONTHLY/YEARLY, INTERVAL, BYDAY ordinals, BYMONTHDAY, BYMONTH, COUNT, UNTIL, WKST, EXDATE, RDATE
- [x] Expand occurrences in event's own time zone, then UTC
- [x] Monthly 31st skip, last-day option; leap day Feb 28 default
- [x] UNTIL UTC Z vs date for all-day
- [x] WKST for weekly interval>1
- [ ] occurrence_cache materialization (repository pending)
- [x] 1,000-instance cap
- [x] property tests (DST, leap, month ends, UNTIL, EXDATE/RDATE)
Acceptance: property tests green.

## Phases 3-10
Not started.
