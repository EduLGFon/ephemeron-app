# TODO

## Environment limits (no SDK/devices here; need owner machine)

- Android SDK unavailable: cold-start measure, release-build verification.
- iOS/macOS/Windows builds not verified locally; web `--wasm` build not
  tested (standard release web build verified working in headless Chrome).
- Migration tests from previous schema versions: none yet (only v1 exists).

## Open work

- Home-screen widgets (Agenda, Next event, Habits today, Focus timer):
  native implementation deferred, needs device verification.
- Flashlight blink and MediaPlayer-on-alarm-stream sound: dropped for now,
  need devices to verify; notification defaults ship instead.

## Deep research remediation (partial)

Completed in this pass: privacy debugPrint cleanup, import order fix, O(N^2) overdue split, agenda FutureBuilder removal, Google API pagination, shared Google color map, unused file removal, formatting, focus timer ValueNotifier, RepaintBoundary on timeline painters, power-saving interval adjustment, ARB metadata parity, tap-target sizing, sync title theme color, settings error retry state, markdown link handling.

Remaining (not yet fixed):
- ValueNotifier for sync title ticker; RepaintBoundary additions; ListView.builder conversions.
- PowerSavingManager implementation and battery-aware sync intervals.
- Localization of remaining hardcoded strings and month/weekday names; ARB metadata parity.
- Loading/error/empty state consistency and form validators.
- Split files >300 lines and functions >40 lines.
- Remove remaining duplication (_now/_enqueue, search sanitization, dialog boilerplate, empty-state widgets, padding).
- Magic number extraction.

## Phase 10 (release hardening, owner checks)

- Security review: code-level done (docs/SECURITY_REVIEW.md); Play
  declaration, backup rules, release-build verification are owner checks.
- Privacy policy: draft done (docs/PRIVACY.md EN/PT); needs lawyer sign-off.
- Store assets, staged rollout: owner.
