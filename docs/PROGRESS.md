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

## Phase 4 - Local calendar (done)
Checklist:
- [x] Event repository with full scope ops single/following/all (7 tests)
- [x] Month grid (custom painter, dots, semantics), 1/3/4/7-day + daily timelines (custom painter, now-line)
- [x] Agenda and year heat-map views
- [x] Event CRUD with editor (calendar, all-day/timed, repeat presets + custom RRULE, keep/reset per-event prompt)
- [x] Drag-to-move with 15-min snap (scope-asked for recurring), tap-empty to create
- [x] Local calendars management, week-start and default-duration settings
- [ ] Device-calendar import, RSVP/attendees UI, Meet links, conflict hints (deferred to Phase 9)
- [ ] 60 fps benchmark on low-end device (env limit; custom painters + RepaintBoundary used)
Acceptance: local calendar usable offline with correct scope semantics. Status: done. Verified: `flutter test` 39 passed, `flutter analyze` clean.

## Phase 5 - Alarms (done, pending device verification)
Checklist:
- [x] Rolling window planner (48 h + 60 future, ordered, request codes, clock-vs-exact routing; 3 tests)
- [x] Native Kotlin module: MethodChannel schedule/cancel, setAlarmClock for medium/strong/constant, exact-while-idle for light
- [x] Full-screen intent notification with Snooze (10 min) and Done actions (no app launch)
- [x] Reboot / time / timezone / locale / update recovery via receivers + direct alarms_index read (no Dart engine needed)
- [x] Constant-alert repeat (1 min, capped 30), missed-alarm marking on reboot
- [x] Ring screen (no back dismiss, 30 s auto-snooze), /ring route
- [x] Permission flows (exact alarm, battery-optimization deep links), OEM guidance, test alarm (10 s)
- [x] iOS/desktop variants (settings note), web unavailable banner
- [ ] Alarm matrix on physical devices (Pixel, Samsung, Xiaomi) - env limit, no Android SDK here
- [ ] Sound on native MediaPlayer alarm stream, vibration pattern, flashlight blink (uses notification defaults for now)
Acceptance: alarm matrix NOT yet run (no devices/SDK). Status: code done, device verification pending. Verified: `flutter test` 42 passed, `flutter analyze` clean.
- [ ] Device-calendar import, RSVP/attendees UI, Meet links, conflict hints (deferred to Phase 9)
- [ ] 60 fps benchmark on low-end device (env limit; custom painters + RepaintBoundary used)
Acceptance: local calendar usable offline with correct scope semantics. Status: done. Verified: `flutter test` 39 passed, `flutter analyze` clean.
