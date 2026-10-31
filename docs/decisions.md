# Decisions

Decisions not covered by PLAN.md (lighter-weight option chosen by default).

- Cancelled exception rows act as EXDATE equivalents; no separate EXDATE column.
- Root `.gitignore` bare `test` rule ignores new test files; force-add them.
- image 4.3.0 has no WebP encoder, so attachment compression re-encodes to JPG q80 (opaque) or resized PNG (alpha) at max 1600 px; files under 200 KB skip re-encoding. No WebP, no version upgrade.
- Native alarm classes lived in `com.example.ephemeron` while the app namespace is `com.spotnik.ephemeron`, so receivers never fired and MainActivity could not resolve AlarmPlugin; moved to `com.spotnik.ephemeron`.
- Alarm snooze keeps the gentle default preset (per-alarm preset is not persisted in alarms_index).
- Meet join uses a tiny `ephemeron/system` channel (ACTION_VIEW) instead of a url_launcher dependency; unsupported platforms fall back to copy-link.
- Dropped without devices/SDK (owner instruction 2026-10-30): physical-device alarm matrix, 60 fps bench, 24 h battery bench, APK/AAB size audit, 3-day real-account soak, MediaPlayer-on-alarm-stream sound, flashlight blink.
- Widget tests: close in-memory Drift DB and unmount inside the test body
  before the final pump; otherwise Drift's stream-close zero-timer trips the
  pending-timer check (addTearDown close runs too late).
