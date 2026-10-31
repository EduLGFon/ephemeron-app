# Deep Research Report: ephemeron-app

Scope: entire Flutter app under `app/` (lib + test), plus AGENTS.md compliance. No code changed during this audit. Report only.

## 1. Method and verification

- Static review of all Dart sources under `app/lib` and `app/test` (123 Dart files, ~43k LOC incl. generated).
- Ran `flutter analyze`: passes with 0 issues.
- `dart format --set-exit-if-changed`: reported 5 files needing formatting (reverted; no commit).
- Cross-checked against AGENTS.md rules (architecture, privacy, performance, imports, tests).
- Did not run `flutter test` or platform builds in this audit.

## 2. Critical privacy and security findings

- `lib/features/auth/presentation/auth_screen.dart:345` logs account email: `debugPrint('WebGoogleButton handle account=${account.email}')`. Personal data in logs. Remove.
- `lib/features/auth/presentation/auth_screen.dart:353` logs full stack trace on auth failure.
- `lib/features/auth/data/google_auth.dart:52` logs account list and active email.
- `lib/features/auth/data/google_auth.dart:233` logs full desktop OAuth URL (may leak code/state). Remove or gate behind debug flag.
- `lib/features/auth/data/google_auth.dart:57,127` log exceptions/stack traces.
- Sync engine has 48 `debugPrint` calls across 5 files; mostly counts/ids but verbose and runs in release. Consider removing or behind a debug flag. None log tokens, but many log remote counts and entity ids.
- `lib/core/config/app_config.dart` ships real OAuth client IDs as defaults (acceptable public identifiers, but backend URL empty by default). Ensure production uses `--dart-define`.
- Backend refresh token stored only in secure storage (good). Google tokens in secure storage (good).
- `app_lock.dart` not fully reviewed here; biometric path clears stale setting on unsupported (good).

## 3. Performance, CPU, and battery

### High-frequency rebuilds
- `lib/features/focus/presentation/focus_screen.dart:252-259`: 1-second `Timer` + `setState` rebuilds entire running view. Should use ValueNotifier + isolated widget (AGENTS.md high-frequency state rule). No ValueNotifier usage anywhere in app.
- `lib/features/sync/presentation/sync_title.dart:22-30`: 1-minute ticker + `setState`.
- `lib/features/calendar/presentation/calendar_screen.dart:50`: `addPostFrameCallback` scheduled inside `build` every rebuild.
- `lib/features/notes/presentation/note_editor_screen.dart:78,97,227`: `setState` full rebuilds on text changes.
- `lib/features/tasks/presentation/tasks_screen.dart:91-97`: O(N^2) overdue split using `contains` inside `where`.

### Missing RepaintBoundary
- Only `lib/features/calendar/presentation/month_view.dart:46` uses RepaintBoundary. Timeline painters (`timeline_view.dart:230,245`), heavy scrolling lists, markdown blocks lack it.

### FutureBuilders recreated in build (repeated DB/API work)
- `lib/features/calendar/presentation/agenda_view.dart:48-71`: `FutureBuilder<Event?>` per occurrence -> N DB queries per build.
- `lib/features/calendar/presentation/event_details_sheet.dart:30,165,228`.
- `lib/features/notes/presentation/note_editor_screen.dart:371-372`.
- `lib/features/settings/presentation/settings_screen.dart:182-183`.
- `lib/features/calendar/presentation/calendar_settings_screen.dart:70-71`.
- `lib/features/alarms/presentation/ring_screen.dart:47-48`.
- `lib/features/notes/presentation/notes_screen.dart:383-384`.

### Sync polling and battery
- `lib/features/sync/application/sync_providers.dart:162,254`: foreground `Timer.periodic` (minutes) without power-saving halving. No `PowerSavingManager` implementation exists despite AGENTS.md requirement.
- Sync intervals fixed at 30 min; no battery-aware adjustment.
- WorkManager background uses `requiresBatteryNotLow: true` (good).

### Heavy loops / recomputation
- `lib/features/focus/application/focus_providers.dart:38-44`: 7 separate DB queries for week minutes.
- `lib/features/habits/presentation/habits_screen.dart:115-129`: O(sections) per habit.
- `lib/features/matrix_screen` grouping loops.
- `lib/features/notes/presentation/markdown_preview.dart:16-21`: markdown parsing on every build, no memoization.
- `lib/features/calendar/presentation/agenda_view.dart:35-39`: regroups each build.

### Lists without virtualization
- `ListView(` with children lists in 20+ screens (tasks, trash, notes, habits, countdowns, agenda, search, matrix, focus, focus stats, auth, calendar settings, alarm settings, sync failed changes, markdown preview, settings, app shell ReorderableListView). Prefer `ListView.builder` for unbounded lists.

### N+1 / repeated queries
- `lib/features/sync/data/backend_sync_engine.dart:165-276`: per-row select/insert in pull loops.
- `lib/features/calendar/presentation/agenda_view.dart:48-71`: N DB lookups per build.

### Scalability
- Google API client uses `maxResults` 250/100 but never follows `nextPageToken`/`nextSyncToken` pagination. Calendars with >250 events or >100 tasks will not fully sync. No `pageToken` handling anywhere.

## 4. Architecture and AGENTS.md compliance

### File/function size
- 23 lib files exceed 300 lines (list in section 8).
- 71 functions exceed 40 lines; largest `build` methods: event_editor_sheet 502 lines, settings 215, notes_screen 146.

### Import order
- Only `lib/features/auth/presentation/auth_screen.dart:20-22` violates (conditional web import after relative imports).

### Formatting
- 5 files not formatted: app_shell.dart, calendar_settings_screen.dart, event_editor_sheet.dart, note_editor_screen.dart, test/tmp_shortcut_test.dart.

### Dead code / unused
- `lib/app/shell/section_placeholder.dart`
- `lib/features/sync/presentation/sync_status_chip.dart`
- `lib/features/sync/presentation/failed_changes_screen.dart`
- `lib/core/result/result.dart` (unused Result type)

### Dynamic / unchecked casts
- `lib/features/settings/data/backup_service.dart:31`: `(r as dynamic).toJson()`
- `lib/data/remote/google_api_client.dart:103,188`: `jsonDecode(r.body) as Map` (raw Map)
- `lib/features/sync/data/sync_engine.dart:628`: `a as Map<String, dynamic>`
- `lib/features/notes/presentation/notes_screen.dart:429,431,433`: redundant casts

### Magic numbers
- 60000 ms/min, 86400000 day ms, 3600000 hour ms scattered across repositories/providers.
- HTTP status literals 401/403/404/409 across remote clients and sync.

### Cross-platform stubs
- AlarmScheduler guards with platform checks (good).
- Desktop alarm sound stub pattern exists (good).
- `google_signin_web_stub.dart` exists (good).
- Need to verify all platform-specific API calls are guarded; `defaultTargetPlatform` usage present in 10 files (likely okay).

### Localization
- Only 3 screens use AppLocalizations (settings, onboarding, search). ~297 Text literals, ~240 unique; only ~34 ARB keys.
- Hardcoded month/weekday names in month_view, year_view, timeline_view, habits_screen.
- Placeholders `(no title)`, `(untitled)`, `(no list)` hardcoded.
- ARB metadata mismatch: `@searchTitle` and `@backupExported` missing from pt ARB.
- AppSections titles hardcoded.

### Hardcoded colors
- Fixed Google palette duplicated in event_editor_sheet and timeline_view.
- `Colors.red/green/white/grey` scattered; not theme-aware in several places.
- Tap targets below 48px: settings_screen and event_editor_sheet CircleAvatar radius 14.

## 5. Duplication (duplicated functions/code)

- `_now()` and `_enqueue()` duplicated in event_repository, habit_repository, task_repository, countdown_repository.
- Search sanitization (`replaceAll('%'/'_')`) duplicated in 4 repositories.
- Google Calendar color map duplicated in event_editor_sheet and timeline_view.
- Rebuild window call duplicated in 4 sites.
- Dialog Cancel/Create boilerplate duplicated across 5 screens.
- Habit log upsert pattern duplicated in habit_repository (3 sites) and backend_sync_engine.
- Empty/error state UI duplicated in tasks, habits, countdowns, notes.
- `Could not load.` text duplicated in 5 screens.
- `MediaQuery.of(context).viewInsets.bottom + 16` padding duplicated in 3 sheets.
- Month/weekday name arrays duplicated in 4 files.

## 6. UI and UX issues

### Loading/error/empty states
- Many screens use `maybeWhen(... orElse: shrink)` hiding loading and errors (alarms, search, timeline, habits, focus dropdowns).
- `settings_screen.dart:56` exposes raw exception `Error: $e`.
- Several error states lack retry (matrix, tasks, notes trash).
- Empty states are plain text in many screens (tasks completed, trash, agenda, failed changes, matrix quadrant).
- Search has no "no results" state.

### Forms
- auth_screen email/password fields have no validators or error text.
- task_editor_sheet title has no validation feedback (silent guard).
- habit/countdown editors only SnackBar for required name.

### Accessibility
- agenda_view event rows lack onTap/semantics to open details.
- markdown_preview link tap recognizer is empty (`onTap = () {}`), links do nothing.
- Many icons lack tooltips.
- Text overflow not consistently handled (tasks title, countdowns subtitle).

### Responsive/layout
- settings dialog fixed width 400.
- month_view fixed 42-cell grid.
- app_shell always bottom navigation; no adaptive rail for wide screens.
- onboarding not reviewed.

### Navigation/modals
- notes_screen pushes NoteEditorScreen without route name.
- tasks_screen completed view pushed as ad-hoc MaterialPageRoute.
- Modal sheets inconsistent `showDragHandle` and `isScrollControlled`.

### Dark/light theme
- Minimal ThemeData; no component themes, text scaling, visualDensity.
- Fixed palette colors may have low contrast in dark mode.
- sync_title uses `Colors.grey` unconditionally.

## 7. Data integrity and compatibility

- Task deletion is soft (isDeleted) (good).
- Schema migrations: only v1 exists; migration tests none (TODO).
- Occurrence cache rebuild on window change; possible duplicate rows if rebuildWindow called concurrently (no guard). Check `_running` style lock not present in OccurrenceRepository.
- No pagination for Google APIs (scalability).
- Backend sync engine pull loops may be O(N*M); not fully reviewed.

## 8. Large files (over 300 lines, lib)

event_editor_sheet.dart 870; sync_engine.dart 757; timeline_view.dart 707; task_repository.dart 557; notes_screen.dart 520; event_repository.dart 516; note_repository.dart 509; settings_screen.dart 500; focus_screen.dart 497; backup_service.dart 488; tasks_screen.dart 476; google_auth.dart 468; note_editor_screen.dart 457; recurrence_rule.dart 430; auth_screen.dart 368; habit_editor_sheet.dart 363; tables.dart 362; occurrence_repository.dart 359; habit_repository.dart 355; backend_sync_engine.dart 345; app_localizations.dart 332; event_details_sheet.dart 328; habits_screen.dart 312.

## 9. Testing gaps

- 26 test files, ~2592 lines.
- No migration tests from previous schema versions.
- No physical-device alarm matrix, battery/perf benchmarks (owner-dropped).
- UI tests likely limited; many screens untested.
- `flutter analyze` passes; tests not run in this audit.

## 10. Recommended priority order

1. Remove personal data from debugPrint (privacy). High.
2. Add ValueNotifier for focus timer and sync title; remove setState per second. Performance.
3. Fix O(N^2) overdue split and FutureBuilders in agenda/event details. Performance.
4. Add Google API pagination for events/tasks. Scalability/data integrity.
5. Guard occurrence rebuild concurrency. Data integrity.
6. Extract shared Google color map, `_now`/`_enqueue`, search sanitization, empty/error state widgets. DRY.
7. Localize hardcoded strings and month/weekday names; fix ARB mismatch. UX/i18n.
8. Add loading/error/empty states and form validators. UX.
9. Split files over 300 lines and functions over 40 lines. Maintainability.
10. Implement PowerSavingManager and battery-aware sync intervals. Battery.
11. Add RepaintBoundary and ListView.builder. Performance.
12. Remove dead code files. Hygiene.
13. Format 5 files. Hygiene.

## 11. Notes

- ARCHITECTURE.md referenced by AGENTS.md was not present in repo at audit time; design contract unavailable. If it exists elsewhere, reconcile.
- README.md at root is default Flutter template; real setup docs in app/README.md (also template). Version pins not documented there; check pubspec.yaml.
- No code changed; all findings are advisory.