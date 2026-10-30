# TODO

## Environment limits (no SDK/devices here; need owner machine)
- Android SDK unavailable: cold-start measure, APK/AAB size, `flutter build apk --split-per-abi`, alarm matrix (Phase 5), 24 h battery benchmark (Phase 10).
- iOS/macOS/Windows builds not verified locally; web `--wasm` build not tested (standard release web build verified working in headless Chrome).
- 3-day real-account Google soak test not run (Phase 6).
- Migration tests from previous schema versions: none yet (only v1 exists).

## Deferred feature work (see PROGRESS.md for phase status)
- Smart-list builder UI; move-between-lists undo snackbar.
- RSVP/attendees UI, conflict hints (Meet links + device-calendar import done).
- Periodic background sync (needs workmanager); alarm sound/vibration/flashlight polish; iOS/desktop variants detail.
- Note backlinks UI, templates, biometric lock, ZIP export, .md import; image WebP compression (image pkg reserved).
- Habit/focus: keep-screen-on, DND toggle, OLED black mode, ongoing notification chronometer, CSV stats export, monthly focus screen, focus stats by tag/habit/time-of-day.
- Backend: periodic auto-sync trigger, export-before-delete flow (JSON backup ships first).

## Phase 9 candidates (in priority order)
1. Widgets/shortcuts/share target; desktop/iOS/web parity (multiple Google accounts done).

## Phase 10 (release hardening)
- Security review: code-level done (docs/SECURITY_REVIEW.md); Play
  declaration, backup rules, release-build verification are owner checks.
- Privacy policy: draft done (docs/PRIVACY.md EN/PT); needs lawyer sign-off.
- Size audit: blocked, no Android SDK (`flutter build apk --split-per-abi`,
  `--analyze-size`, web payload).
- Battery: 24 h benchmark blocked, no device.
- Store assets, staged rollout: owner.
