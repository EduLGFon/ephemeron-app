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

- Migration tests from previous schema versions: none yet (only v1 exists).
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

- iOS home-screen widgets: add WidgetKit extension target, App Group, and SwiftUI widgets mirroring Android types.
- Flashlight blink and MediaPlayer-on-alarm-stream sound; notification defaults
  ship instead.
- Alarms follow-up: done. Task custom reminder offsets (per-task JSON,
  at-time default preserved), focus end alarm preset picker (stored per
  session, scheduled with that style, cancelled on finish/discard), iOS
  Critical Alerts entitlement (`ios/Runner/Runner.entitlements`, versioned via
  .gitignore ladder) plus `AlarmScheduler.requestCriticalAlerts` and a
  settings request button.
- iOS owner steps (need Xcode Mac + Apple approval, unverifiable on Linux):
  select Runner.entitlements under Signing and Capabilities in Xcode
  (CODE_SIGN_ENTITLEMENTS), add a `requestCriticalAlerts` handler on the
  `ephemeron/alarms` channel calling
  `UNUserNotificationCenter.current().requestAuthorization(options:
  [.alert, .sound, .criticalAlert])`, request the Critical Alerts entitlement
  in App Store Connect.
- Alarm migration test v4->v5 (countdowns.alarm_preset, alarms_index
  kind/title/preset): schema migrates, no dedicated migration test yet.

## Deep research remediation (partial)

Remaining (not yet fixed):

- Split files >300 lines and functions >50 lines (optional cleanup).

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

## Microsoft sync foundation (2026-11-04)

- Web sign-in still needs `app/web/auth.html` (or equivalent redirect page) and the Entra SPA redirect registration for `http://localhost:8080/auth.html`; the service already uses `AppConfig.microsoftWebRedirectUri`. Android is the primary verification target until then.

- Task action sheet: projected future occurrences are read-only until per-occurrence completion is implemented (no completion/won't-do actions shown).
