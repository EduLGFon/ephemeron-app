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
- [ ] occurrence_cache materialization repository (pending)
- [x] 1,000-instance cap
- [x] property tests (DST, leap, month ends, UNTIL, EXDATE/RDATE)
Acceptance: property tests green. Status: done (domain layer).

## Phase 3 - Tasks, lists, tags, smart lists, trash, quick add (partial)
Checklist:
- [x] Eisenhower classification (domain)
- [x] Recurring task next-due helper (domain)
- [x] Natural language date/time parser EN + PT (domain)
- [ ] Task/list/tag repositories and UI (not started)
- [ ] Undo, trash, smart lists (not started)
Acceptance: NOT yet (no full local task flow). Status: partial.

## Phases 4-10
Not started.
