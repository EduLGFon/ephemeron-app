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

## Phase 10 (release hardening, owner checks)

- Security review: code-level done (docs/SECURITY_REVIEW.md); Play
  declaration, backup rules, release-build verification are owner checks.
- Privacy policy: draft done (docs/PRIVACY.md EN/PT); needs lawyer sign-off.
- Store assets, staged rollout: owner.
