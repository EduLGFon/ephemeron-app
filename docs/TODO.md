# TODO

## Owner / device verification (no SDK/devices here)

- Week calendar home widget: verify Android native build and launcher behavior.
- Week widget tap navigation: warm/cold launcher tap behavior still needs owner
  device verification (app-shell restore race fix applied, unverified).
- Android alarm `AlarmRingService` (flashlight blink + MediaPlayer on alarm
  stream) implemented; verify on device (reminder/notification presets unchanged).
- Google sign-in + runtime permissions: verify sign-in on Android (debug +
  release), decline path, device-calendar import/settings, first reminder save
  / alarm test prompts, exact-alarm/full-screen prompts for clock/lock-screen
  presets. Google Cloud console owner steps still required (SHA-1 entries,
  Calendar/Tasks APIs, Web `serverClientId` match).
- Microsoft web sign-in: `app/web/auth.html` added; Entra SPA redirect
  registration for `http://localhost:8080/auth.html` still required (owner
  console). Android remains primary verification target.
- Full `flutter test` suite not run here (timed out in this env); targeted
  tests pass.
- Device profile run for startup/calendar rebuild timings still useful.
- Samsung SM A556E widget verification was interrupted by USB disconnect.

## Code follow-ups

- Split files >300 lines and functions >50 lines (U10 partial): `event_editor_sheet.dart`, `task_editor_sheet.dart`, `event_details_sheet.dart`, `app_shell.dart`, `tasks_screen.dart`, `note_editor_screen.dart`, `habit_editor_sheet.dart`, `habits_screen.dart`, and `event_repository.dart`/`occurrence_repository.dart` still need safe re-splits (prior extension-in-parts splits reverted after importer breakage). `task_repository`, `sync_engine`, `home_widget_data_binder`, and `focus_screen` are split.
- Microsoft remote deletions: event and calendar remote deletions still not
  reconciled (calendar view is time-windowed). Task list/task deletions are
  reconciled conservatively on successful full-scope/list fetches.
- Projected task occurrence completion: uncompleting a suppressed projected
  occurrence has no calendar-surface undo yet (`TaskRepository.uncompleteTaskOccurrence` exists).
- Week widget: Motorola One Fusion filled a 4x2 cell (dark 3-day range) and setup
  dialog persisted theme/day count; recheck after device verification.
- Migration tests: full step-by-step Drift schema snapshot replay is not set up
  (v4->v5 and v7/v11 regressions are covered).

## UX / behavior gaps

- Task-list and smart-list chip long-press management has no widget test.
- Habit agenda rows and "Open habits" navigation covered by repository/static
  checks only (month/timeline markers and tap action sheet have widget tests).
- Long-press drag reorder has no dedicated widget test (`docs/TASK_DATES_AND_SORTING.md`).
- CalendarScreen 2 s session-restore fallback can trigger one duplicate initial
  build if settings loading stalls longer than 2 s.
- Matrix AsyncNotifier fallback can briefly render Auto on cold start before a
  saved Priority mode arrives.
- Timeline/agenda rows do not show account/calendar source labels (task tiles,
  task details, event details do); adding without per-row queries needs source
  columns in occurrence cache.
- Matrix and task-editor layout tests cover 320 dp at default text scale; very
  large accessibility text scaling is not covered.
- Recurring Google series cannot move between Google accounts (Google has no
  single-token cross-account move); moving such a series to a local calendar is
  supported. Cross-account copy/delete requires both accounts synced at least
  once; if the source account is removed before its delete op runs, the old
  remote row can remain.
- Task subtasks keep their own list/source when a parent task is moved; moving
  a whole subtask tree is not automatic.

## iOS (owner / macOS + Xcode)

- Home-screen widgets not implemented: requires WidgetKit extension target, App
  Group entitlement, signing, and SwiftUI views mirroring Android providers
  (`docs/IOS_WIDGETS.md`). Do not fabricate Xcode project integration on Linux.
- Critical Alerts owner steps: select `Runner.entitlements` under Signing and
  Capabilities, add `requestCriticalAlerts` handler on `ephemeron/alarms`
  (`UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .criticalAlert])`), request entitlement in App Store Connect.

## Phase 10 / release (owner)

- Security review code-level done (`docs/SECURITY_REVIEW.md`); Play declaration,
  backup rules, release-build verification are owner checks.
- Privacy policy draft done (`docs/PRIVACY.md` EN/PT); needs lawyer sign-off.
- Store assets, staged rollout: owner.

## Dependencies / build

- `wakelock_plus` left at 1.8.0 (1.8.2 unreachable: conflict with
  `battery_plus` 7.1.2 via `dbus`). Revisit when either package relaxes.
- Deferred: AGP 9.3 + Gradle 9.5 upgrade (needs migration and build
  size/behavior comparison).
- Do not run a release build while `flutter run` is active (both rewrite
  `GeneratedPluginRegistrant.java`; debug registrant includes `integration_test`
  and release Java compile fails).
