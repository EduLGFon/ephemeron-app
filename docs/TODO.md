# TODO

## Environment limits (no SDK/devices here; need owner machine)

- Migration tests from previous schema versions: none yet (only v1 exists).

## Open work

- Home-screen widgets (Agenda, Next event, Habits today, Focus timer)
- Flashlight blink and MediaPlayer-on-alarm-stream sound; notification defaults
  ship instead.

## Deep research remediation (partial)

Remaining (not yet fixed):

- ListView.builder conversions for remaining mixed/static lists.
- Split files >300 lines and functions >40 lines (optional cleanup).
- Dialog boilerplate, empty-state widget, and padding deduplication (optional
  cleanup).
- Auth screen email/password validation.

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
