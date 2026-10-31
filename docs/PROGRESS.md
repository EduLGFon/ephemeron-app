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
- [x] Tasks UI: lists filter, overdue + reschedule-all, swipe complete/delete, move-to-list with undo, editor, trash, completed, matrix
- [x] Undo snackbars (6 s delete; complete; reopen from completed)
- [x] Undo snackbars (6 s delete; complete; reopen from completed; move-between-lists)
Acceptance: full local task flow offline with undo. Status: done. Verified: `flutter test` 32 passed, `flutter analyze` clean.
Note: parallel owner commit 1928290 restructured task screens; integrated on top.

## Phase 4 - Local calendar (done)
Checklist:
- [x] Event repository with full scope ops single/following/all (7 tests)
- [x] Month grid (custom painter, dots, semantics), 1/3/4/7-day + daily timelines (custom painter, now-line)
- [x] Agenda and year heat-map views
- [x] Event CRUD with editor (calendar, all-day/timed, repeat presets + custom RRULE, keep/reset per-event prompt)
- [x] RSVP responses (Accept/Maybe/Decline, queued to outbox), Meet join via system browser + copy fallback, conflict hint on overlap
- [x] Drag-to-move with 15-min snap (scope-asked for recurring), tap-empty to create
- [x] Local calendars management, week-start and default-duration settings
- [x] Device-calendar import (device_calendar_plus, permission-gated, Android/iOS; degrades elsewhere)
Acceptance: local calendar usable offline with correct scope semantics. Status: done. Verified: `flutter test` 39 passed, `flutter analyze` clean.
Note: device frame-rate benchmark dropped (no test devices); render path uses custom painters + RepaintBoundary.

## Phase 5 - Alarms (done)
Checklist:
- [x] Rolling window planner (48 h + 60 future, ordered, request codes, clock-vs-exact routing; 3 tests)
- [x] Native Kotlin module: MethodChannel schedule/cancel, setAlarmClock for medium/strong/constant, exact-while-idle for light
- [x] Full-screen intent notification with Snooze (10 min) and Done actions (no app launch)
- [x] Reboot / time / timezone / locale / update recovery via receivers + direct alarms_index read (no Dart engine needed)
- [x] Constant-alert repeat (1 min, capped 30), missed-alarm marking on reboot
- [x] Alarm sound/vibration per preset via notification defaults (strong/constant vibrate); native package-name fix (was com.example.ephemeron); system channel (openUrl, DND access, focus chronometer)
- [x] Ring screen (no back dismiss, 30 s auto-snooze), /ring route
- [x] Permission flows (exact alarm, battery-optimization deep links), OEM guidance, test alarm (10 s)
- [x] iOS/desktop variants (settings note), web unavailable banner
Acceptance: code done. Status: done. Verified: `flutter test` 98 passed, `flutter analyze` clean.
Note: physical-device alarm matrix, MediaPlayer-on-alarm-stream sound and flashlight blink dropped (need devices/SDK).

## Phase 6 - Google sync (done)
Checklist:
- [x] Thin hand-written REST client (events.list/insert/patch/delete, calendarList, tasks, tasklists), etag/If-Match, 410/401/403/429 typed errors, Retry-After
- [x] Mappers: Google <-> Drift, local-only fields preserved (alarmPreset, colorId, task dueTime/priority/rrule)
- [x] Single-flight sync engine: outbox push ordered per entity, backoff+jitter, 410 full resync (keeps dirty), etag 412 refetch-and-reapply, failed-changes list with Retry/Discard
- [x] Fake-server suite (7 tests): token round-trip, 410, push/etag, 412, 429, offline, partial failure, idempotent resume
- [x] Google auth (sign_in v7, incremental Calendar then Tasks scopes), consent-first screen, works-without-account, keystore token storage
- [x] Sync status chip (Synced/Syncing/Offline/Error), sync triggers
- [x] Periodic background sync via WorkManager (constrained periodic task, headless Google + backend engines; best-effort)
- [x] Google data never touches backend: re-verified in Phase 8 (backend code imports no Google code, touches only habit/focus tables)
Acceptance: fake-server suite green. Status: done. Verified: `flutter test` 98 passed, `flutter analyze` clean.
Note: 3-day real-account soak dropped (needs owner account + days of device time).
New deps (pinned exact): http 1.6.0 (thin REST client, avoids heavy googleapis), google_sign_in 7.2.0 (OAuth), flutter_secure_storage 11.2.0 (keystore). Size check deferred (no Android SDK here).

## Phase 7 - Notes (done)
Checklist:
- [x] Folders: nested, breadcrumbs, move (cycle-safe), delete reparents children
- [x] Notes CRUD, pin, duplicate, trash/restore with undo, trash screen, biometric app lock (local_auth, settings toggle, unsupported devices pass through)
- [x] Markdown editor: toolbar, edit/preview toggle, tappable checklists, word/char count, autosave 800 ms
- [x] Custom lightweight preview renderer (gitHub flavored, lazy ListView, cached per version)
- [x] FTS5 search with highlighted snippets
- [x] Attachments: compressed store (max 1600 px, JPG q80 / PNG for alpha; image pkg has no WebP encoder) + orphan cleanup (file_picker import UI)
- [x] Event-linked notes: add from event details, list in details, overflow notes for >8000 chars
- [x] Backlinks UI ([[Title]] links, incoming chips, tap-to-create), .md/.txt import (note templates + ZIP export done)
Acceptance: notes usable offline with folders, search, preview. Status: done. Verified: `flutter test` 98 passed, `flutter analyze` clean.
New deps (pinned exact): markdown 7.3.1 (parser only, custom renderer), image 4.3.0 (reserved for attachment compression). Size check deferred (no Android SDK).

## Phase 8 - Habits, countdowns, focus (done)
Checklist:
- [x] Habit streak engine (domain, skip-neutral) + date keys + countdown date math
- [x] Habit (outbox rows)/countdown/focus repositories (3 tests)
- [x] Habit/countdown/focus providers + UI screens (all tabs wired)
- [x] Focus timer from stored startedAt/targetEndUtc + AlarmScheduler end alarm (no polling; per-second tick only while running view visible)
- [x] Backend auth REST client + changeset sync for habits/focus with fake-server tests; Google isolation re-verified (backend code imports no Google code, touches only habit/focus tables)
- [x] Backend account UI (AuthScreen section, settings entry, sync triggers, export-first remote-data deletion, habits/focus auto-sync interval)
- [x] Focus monthly heat-map screen + stats by task/habit/time-of-day (last 30 days), CSV export, alarms-only DND toggle, OS chronometer notification, OLED black mode
Acceptance: timers survive app kill, streaks correct. Status: Phase 8 done, verified `flutter test` 98 passed, `flutter analyze` clean.
Notes: dialog TextEditingControllers are intentionally not disposed (disposal races the pop transition). Widget tests mock the ephemeron/alarms channel.
Notes: bestStreak bridges skipped days without extending the run (matches currentStreak). Backend push is cursor-based for logs/focus (their repos enqueue no outbox rows; harmless). Focus weekly streaks ignore skipped; `finishSession` abandoned param unused.

## Phase 9 - Polish (done except widgets)
Checklist:
- [x] JSON backup + restore (21 tables, validated, transactional; attachment bytes excluded)
- [x] Global search across entities (tasks/events/notes/habits/countdowns/tags; display-only rows)
- [x] Onboarding (3 pages max, skip always; permissions at moment of need)
- [x] Localization scaffolding (ARB EN/PT, delegates, language setting; search/backup/onboarding migrated)
- [x] Accessibility pass (timer semantics, excluded decoration, stepper tooltips, weekday labels)
- [x] Launcher shortcuts (New task/event, Start focus), Android share-target text into quick add; multiple Google accounts; iOS 64-limit note; desktop in-app notes
- [ ] Home-screen widgets (Agenda/Next event/Habits/Focus; needs device verification, deferred)
- [x] Web parity verified: boots with zero console errors, Drift opens via vendored WASM (IndexedDB fallback), DB reads/writes persist, all tabs + Search + Settings + Account + reorder sheet exercised in headless Chrome (debug + release)
Acceptance: each item shippable alone. Status: done except home-screen widgets. Verified: `flutter test` 98 passed, `flutter analyze` clean.
New deps (pinned exact): workmanager 0.10.10 (periodic background sync), file_picker 13.3.0 (.md/.txt import), local_auth 3.0.2 (biometric app lock). Native build unverified (no Android SDK here).
Notes: flutter_gen synthetic package is deprecated here; gen-l10n writes gitignored lib/l10n/src. Root README.md and ARCHITECTURE.md referenced by AGENTS.md do not exist (app/README.md does).

## Phase 10 - Release hardening (code done; owner checks open)
Checklist:
- [x] Code-level security review (docs/SECURITY_REVIEW.md)
- [x] INTERNET permission on release builds (was debug/profile-only)
- [x] Privacy policy draft EN/PT (docs/PRIVACY.md, needs lawyer sign-off)
- [ ] Store assets, staged rollout (owner)
Acceptance: code gates pass. Status: code items done; store items are owner checks.
Note: 24 h battery benchmark and APK/AAB/web size audit dropped (need devices + SDK).