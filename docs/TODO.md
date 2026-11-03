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
