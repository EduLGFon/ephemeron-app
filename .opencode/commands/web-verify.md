---
description: Verify the Ephemeron Flutter app in a real browser via the in-app browser
---

Serve the Ephemeron app for web and verify this flow in a real Chromium tab, reporting console errors and screenshots: $ARGUMENTS

If $ARGUMENTS is empty, run the default pass: boot with no console errors, complete onboarding, open every bottom-nav tab (Calendar, Tasks, Matrix, Habits, Countdowns, Focus via More, Notes via More), push the Search route, run one search query, open Settings > Account, and tap Google sign-in (expect the "not configured" snackbar, not a crash).

Procedure (in-app browser tools run inside the `execute` Code Mode tool; call them as `tools.browser.*` after `search({namespace:"browser"})`):

1. Start the server in the background from `app/`: `flutter run -d web-server --web-port 8099`. For release verification instead: `flutter build web --release`, then serve `app/build/web` on 8099 with `python3 -m http.server`. Confirm the port listens before continuing.
2. Open a tab to `http://localhost:8099/`, wait for load, and read `console` at level `error`. Zero errors is the bar.
3. The app renders to canvas, so `snapshot` shows almost no text. Verify visually with `screenshot`, and drive input this way:
   - Clicks: dispatch synthetic `PointerEvent`s on the canvas inside the `flt-glass-pane` shadow root (`pointerover`, `pointerdown`, `pointerup` with `pointerId: 1`, `pointerType: 'mouse'`). Tapping nav destinations and sheet rows works; buttons that open modal sheets sometimes ignore synthetic events.
   - Modal sheets, text fields, and stubborn buttons: use keyboard instead — Tab to traverse, Enter to activate. A focused Flutter text field exposes a DOM `textbox` ref you can `fill`.
   - `evaluate` scripts run once and return JSON; there are no timers. Chain small steps across calls and re-screenshot after each one.
4. Cover the flow end to end, checking `console` errors after every screen change. Known-good reference: onboarding (3 pages) → Calendar grid from the WASM DB → Habits day strip → Countdowns create round-trip → Search push + query → Settings/Backup web note → Account Google guard snackbar → Focus/Notes/Matrix/Tasks render.
5. Report: what was exercised, every console error verbatim (or "zero console errors"), and the screenshot paths for the user to view. Do not fix failures unprompted; list them as findings unless asked.

Notes: first load compiles Dart to JS and can take minutes — wait via repeated short `wait` calls, never fixed sleeps. `flutter test -d chrome` cannot drive `integration_test/` ("Web devices are not supported for integration tests yet"); this command is the web driver. Kill the server when done and leave `git status` clean of scratch files.
