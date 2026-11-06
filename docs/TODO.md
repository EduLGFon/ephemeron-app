# TODO

## Test health (2026-11-02, found while splitting the timeline view)

- `widget_test` "app builds" hung 10 min: `db.close()` deadlocks on drift's
  stream-cache `Timer.run` completers when streams were cancelled after the
  last pump (fake-async timers never fire while awaiting close). Fixed by
  unmounting first, then pumping twice (second with a 1 s duration to flush
  the chained cache timers) before `close()`; test now passes in ~3 s.
  A 3-minute per-test timeout guards against future 10-minute CI burns.
- `db_test` schema pin fixed: bumped to 7 with a day-index assertion
  (was pinning 6 while the code had migrated to 7).
- `log/linux` real-run errors fixed: `HeatmapImage`/`WeekBarsImage` used
  `Expanded`/`FractionallySizedBox` under unbounded height (offscreen
  widget-image renders) -> now fixed-size cells via `LayoutBuilder` with a
  bounded fallback, plus unbounded-height layout tests; `home_widget`
  `MissingPluginException` on Linux (no widget host) is now skipped
  silently at the `HomeWidgetService` boundary instead of crashing
  unhandled out of `main()`.
  Follow-up: the service-level catch was not enough. `home_widget` 0.7.0
  `renderFlutterWidget` fires an unawaited `saveWidgetData` that escapes
  try/catch as an unhandled async error (3x log spam on Linux, one per
  image). Now guarded before calling via `isHomeWidgetSupported`
  (Android/iOS only) in `home_widget_service`, `widget_image_service`,
  `home_widget_data_binder._refreshImages`, and
  `home_widget_refresh_service`; tests pin the Linux skip.

## Environment limits (no SDK/devices here; need owner machine)

- Migration tests from previous schema versions: v4->v5 alarm/countdown
  coverage added (`alarm_migration_v4v5_case.dart`,
  `migration_v4_v5_case.dart`) plus v7/v11 regression coverage
  (`migration_v7_v11_regression_case.dart`). Full step-by-step schema
  snapshot replay is not set up.
- Week calendar home widget: Android grid/provider/layout added (7 day
  columns, all-day band, timed blocks, day tap deep link, 1dp minimum size).
  No Android SDK/device here, so the native build and launcher behavior are
  not verified yet.

## Calendar and task UX pass (2026-11-04)

- All-day `Events.endDate` is now exclusive, matching Google Calendar. Legacy
  rows with `endDate == startDate` render as one day; no data migration was
  needed. Device-calendar imports are normalized to the same invariant.
- Task-list and smart-list chips use long-press for management. No widget test
  covers the long-press gesture yet; the manager screens and repository paths
  are covered.
- Habit markers are widget-tested in the month grid and timeline strip, and the
  tap action sheet is covered by a month widget test. Agenda habit rows and the
  "Open habits" navigation are covered by repository and static checks only.
- Task sort menus and planned/due date fields are covered by repository,
  occurrence and settings tests. Long-press drag reorder has no dedicated
  widget test; see `docs/TASK_DATES_AND_SORTING.md`.
- The note editor styles Markdown inline in the same field but keeps the
  markers visible and dimmed. It is not a full WYSIWYG editor that hides
  markers; this preserves cursor and Android IME offsets.

## Open work

- iOS home-screen widgets: not implemented here. Requires macOS + Xcode owner
  work: WidgetKit extension target, App Group entitlement, signing, and
  SwiftUI views mirroring the Android providers. See `docs/IOS_WIDGETS.md`.
  Linux agents must not fabricate Xcode project integration.
- Android alarm flashlight blink and MediaPlayer-on-alarm-stream sound are
  implemented in `AlarmRingService` (native foreground service); reminder and
  notification presets keep notification defaults. Unverified on device.
- iOS owner steps (need Xcode Mac + Apple approval, unverifiable on Linux):
  select Runner.entitlements under Signing and Capabilities in Xcode
  (CODE_SIGN_ENTITLEMENTS), add a `requestCriticalAlerts` handler on the
  `ephemeron/alarms` channel calling
  `UNUserNotificationCenter.current().requestAuthorization(options:
  [.alert, .sound, .criticalAlert])`, request the Critical Alerts entitlement
  in App Store Connect.

## Deep research remediation (partial)

Remaining (not yet fixed):

- Split files >300 lines and functions >50 lines (in progress / being
  addressed in the integration pass).

## Phase 10 (release hardening, owner checks)

- Security review: code-level done (docs/SECURITY_REVIEW.md); Play declaration,
  backup rules, release-build verification are owner checks.
- Privacy policy: draft done (docs/PRIVACY.md EN/PT); needs lawyer sign-off.
- Store assets, staged rollout: owner.

## Dependency update (2026-10-30)

- Updated archive 3.6.1->4.5.2, battery_plus 6.2.3->7.1.2, device_calendar_plus
  0.7.1->0.12.0, go_router 18.1.1->18.1.2, image 4.3.0->4.12.0 and transitive
  deps; regenerated Drift code.
- wakelock_plus left at 1.8.0 (latest 1.8.2 unreachable): upstream conflict
  between wakelock_plus >=1.8.1 (dbus ^0.8.0) and battery_plus 7.1.2 (upower
  0.7.0 -> dbus ^0.7.0). Revisit when either package relaxes.

## Google sign-in + runtime permissions (2026-10-31, needs device check)

- Google Cloud console (owner): Android OAuth client must match package
  `com.spotnik.ephemeron` plus debug AND release SHA-1; Web client supplies
  `serverClientId` (code now passes the web ID on Android). Enable Calendar
  and Tasks APIs. Without the SHA-1 entry sign-in fails with reauth/canceled.
- Device check: sign-in on Android (debug + release), decline path shows the
  real error; device-calendar import prompts and appears in app settings;
  first reminder save / alarm test prompts for notifications; exact-alarm
  and full-screen prompts fire only for clock / lock-screen presets.
- `flutter test` full suite not run here (timed out in this env); targeted
  `auth_screen`, `focus_screen`, `countdowns_screen` tests pass.
  `flutter analyze` clean.

## UX/performance pass (2026-11-04)

- Startup and calendar rebuild timings were validated structurally and by tests,
  not measured on a device. The app defers non-critical launch work and batches
  occurrence inserts; a device profile run is still useful.
- The 2 s session-restore fallback in CalendarScreen can trigger one duplicate
  initial build if settings loading stalls longer than that. Normal settings
  reads complete well before it.
- Matrix persists its mode, but an AsyncNotifier fallback briefly renders Auto
  on cold start before a saved Priority mode arrives.
- Focus Stopwatch mode is intentionally not persisted; focus/break remain the
  restored modes. Stopwatch sessions longer than 12 h show the existing
  recovered-session banner.
- Account/calendar source labels are shown in task tiles, task details and
  event details. Timeline and agenda rows do not show them yet; doing that
  without per-row queries needs source columns in the occurrence cache.
- Matrix and task-editor layout tests cover 320 dp at default text scale; very
  large accessibility text scaling is not covered.
- Source moves: recurring Google series cannot move between Google accounts
  (Google has no single-token cross-account move); moving such a series to a
  local calendar is supported. Cross-account copy/delete requires both source
  and destination accounts to sync at least once; if the source account is
  removed before its delete op runs, the old remote row can remain.
- Task subtasks keep their own list/source when a parent task is moved; moving
  a whole subtask tree is not automatic.

## Build performance (2026-11-03)

- `flutter build apk` on the owner laptop is I/O bound on a 5400 RPM HDD.
  Analysis, applied Gradle settings and the single-ABI helper are in
  `docs/BUILD_PERFORMANCE.md` and `tools/build_apk.sh`. An SSD is the only
  large hardware fix.
- Dev loop: `tools/run_android.sh` reuses one debug APK with
  `--use-application-binary` and skips Gradle (about 12s instead of 37s to
  1 min warm). It rebuilds the APK only for native or dependency changes.
- Web: each `flutter run -d chrome` recompiles for the web (about 1:45) and a
  warm cache does not help. Keep one session and use hot restart (`R`).
- Deferred: AGP 9.3 + Gradle 9.5 upgrade (build-speed work; needs a migration
  and a build-size/behavior comparison).
- Do not run a release build while `flutter run` is active. Both rewrite
  `GeneratedPluginRegistrant.java`; a debug registrant includes
  `integration_test` and the release Java compile fails.

## Widget and sync handoff (2026-11-05)

- Week widget: the image-fill fix is merged. App-shell widget tap handling was
  updated so widget navigation is not overwritten by async session restore;
  warm/cold launcher tap behavior still needs owner device verification. On a
  Motorola One Fusion the widget filled a 4x2 cell and setup persisted
  theme/day count; Samsung SM A556E verification was interrupted by a USB
  disconnect.
- Microsoft sync: schema v12, read-only pull, and the `microsoft-ui-sync`
  follow-up (global sync loop, source labels and pickers) are merged
  (c175177 / 9b051b7). Graph access remains read-only.
- Microsoft item edits and completions are hidden/disabled in the UI (local-only
  Graph writes not supported).
- Microsoft remote deletions are reconciled conservatively for task lists and
  tasks on successful full-scope/list fetches (dirty rows preserved). Event and
  calendar remote deletions are still not reconciled because calendar view is
  time-windowed.

## Microsoft sync foundation (2026-11-04)

- `app/web/auth.html` was added for the flutter_web_auth_2 web callback.
  Entra SPA redirect registration for `http://localhost:8080/auth.html` is
  still an owner console step; the service already uses
  `AppConfig.microsoftWebRedirectUri`. Android is the primary verification
  target until then.
- Projected task occurrences support per-occurrence completion/won't-do state
  (local-only). The calendar action sheet routes projected occurrences to
  occurrence-aware actions; uncompleting a suppressed projected occurrence has
  no calendar-surface undo yet (repository method exists).
- Alarm migration v4->v5 is covered by automated tests, and the v7/v11
  `occurrence_cache.source_type` duplicate-column migration bug is fixed with
  regression coverage.

## Habit deletion (2026-11-05)

- Soft-delete with 6s undo buffer added for habits: `HabitRepository.deleteHabit`/`restoreHabit`, `PendingOperations.scheduleHabitDelete`, apply case, UI affordances on tile and editor sheet. Outbox op enqueued. Calendar entries exclude deleted. Tests: `habit_delete_case.dart`.

## Timeline persistence (2026-11-05)

- Timeline zoom (manual scale) and vertical scroll offset now persist via SharedPreferences (calendar.timelineScale, calendar.timelineScrollOffset); one global value shared by day and multi-day views. Restore happens on first mount; scroll offset clamps to max extent. Tests: `timeline_persist_case.dart`.
