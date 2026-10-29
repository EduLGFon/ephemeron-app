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
- [x] occurrence_cache materialization repository (window rebuild, cancelled-exception exclusion, tz-aware dayKey, invalidate, watchDay stream)
- [x] 1,000-instance cap
- [x] property tests (DST, leap, month ends, UNTIL, EXDATE/RDATE)
Acceptance: property tests green. Status: done. Verified: `flutter test` 24 passed, `flutter analyze` clean.
Note: root .gitignore bare `test` rule ignores new test files (meant for platform scaffolding); new tests force-added. Cancelled exception rows act as EXDATE equivalents; no separate EXDATE column.

## Phase 3 - Tasks, lists, tags, smart lists, trash, quick add (done)
Checklist:
- [x] Eisenhower classification (domain)
- [x] Recurring task next-due helper (domain, from_due_date/from_completion_date, skip)
- [x] Natural language date/time parser EN + PT (domain, case-preserving)
- [x] Quick-add shorthand parser #tag ~list -p1..-p4 (domain, tested)
- [x] Task/list/tag/smart-list repository with outbox rows, trash, restore, purge, subtasks
- [x] Tasks UI: lists filter, overdue + reschedule-all, swipe complete/delete, editor, trash, completed, matrix
- [x] Undo snackbars (6 s delete; complete; reopen from completed)
- [ ] UI for move-between-lists undo, smart-list builder screen (repo supports filters; builder deferred to Phase 9 polish)
Acceptance: full local task flow offline with undo. Status: done. Verified: `flutter test` 32 passed, `flutter analyze` clean.
Note: parallel owner commit 1928290 restructured task screens; integrated on top.

## Phases 4-10
Not started.
