# Ephemeron — Step 0: Foundation

Project scaffold, routing, DI, local DB schema skeleton, and base theming.
No feature logic yet — this is the ground the rest of the MVP build order
gets built on.

## What's included

- **Riverpod** as both state management and DI (`core/settings`,
  `data/local/database_provider.dart`) — no separate service locator.
- **go_router** with `StatefulShellRoute.indexedStack` — 7 branches (one
  per section), each preserving its own navigation state when you switch
  tabs. All 7 exist in the router regardless of which are visible.
- **AppShell** — the bottom nav bar itself only shows 5 pinned sections +
  a "More" sheet for the rest (see `nav_section.dart` for the reasoning:
  7 destinations in one bar exceeds Material's own guidance). Swap
  `pinnedSectionsProvider` for a SharedPreferences-backed version later to
  make this user-customizable/reorderable without touching routing.
- **Drift** local database with skeleton tables for Lists, Tags, Tasks,
  TaskTags, Habits, HabitLogs, FocusSessions, Countdowns. Field sets are
  intentionally minimal — they get filled in during their respective MVP
  build steps (Tasks in step 3, Habits in step 6, Focus in step 7).
- **Theme** — a named palette (petrol/amber, tied to the app's own
  ephemeral-tasks/harvest metaphor) and a Fraunces+Inter type pairing,
  bundled as local font assets rather than fetched at runtime, plus a
  `reducedMotion` hook already wired into page transitions.
- 7 placeholder screens, one per section.

## What's deliberately NOT here yet

- Google OAuth / Calendar API client (Step 1)
- Full-screen alarm engine (Step 2)
- Real Tasks CRUD + Google Tasks mirror (Step 3)
- Actual reorder/customize UI for the bottom bar

## Setup

1. Install the Flutter SDK (stable channel) if you haven't already.
2. Download two font families from fonts.google.com and drop the files
   into `assets/fonts/` matching the filenames in `pubspec.yaml`:
   - **Fraunces** — Regular + SemiBold
   - **Inter** — Regular, Medium, SemiBold
   (This project bundles fonts locally instead of using the `google_fonts`
   package specifically to avoid a runtime network fetch — see the
   battery/lightweight goal from the brainstorm.)
3. Enable desktop targets if you're planning to build for them:
   ```
   flutter config --enable-linux-desktop --enable-windows-desktop
   ```
4. Install dependencies:
   ```
   flutter pub get
   ```
5. Generate Drift's `database.g.dart` (required — the project won't
   compile without this step):
   ```
   dart run build_runner build --delete-conflicting-outputs
   ```
   Use `dart run build_runner watch --delete-conflicting-outputs` instead
   while actively editing tables, so it regenerates on save.
6. Run:
   ```
   flutter run
   ```

## Step 1: Auth

Two fully independent auth systems, on purpose (see the CASA-avoidance
architecture from the design discussion — the backend must never touch
Google tokens or data):

- **Google Calendar** (`features/auth/google/`) — identity + Calendar-
  scope authorization via `google_sign_in` ^7. Covers Android + Web only;
  a desktop (Windows/Linux) implementation is a separate future class
  behind the same `GoogleAuthRepository` interface, using a loopback-
  redirect OAuth flow instead — nothing above that layer will need to
  change when it's added.
- **Backend account** (`features/auth/backend/`) — email/password against
  your own not-yet-built backend. `HttpBackendAuthRepository` implements
  the REST contract documented at the top of `backend_auth_repository.dart`
  (`/auth/register`, `/auth/login`, `/auth/refresh`, `/auth/logout`) —
  point `AppConfig.backendBaseUrl` at your real backend once it exists;
  until then, login/register will fail with a connection error, which is
  expected.

### If you've used `google_sign_in` before v7

The API changed significantly: singleton `GoogleSignIn.instance`,
mandatory `initialize()`, and authentication (`authenticate()`) split
from authorization (`account.authorizationClient.authorizeScopes(...)`).
Notably, `GoogleSignIn.currentUser` was removed — nothing tracks "who's
signed in" for you anymore, which is why `GoogleSignInAuthRepository`
keeps its own reference from the authentication events stream. If
anything here doesn't match what you remember, check the current
[migration guide](https://pub.dev/packages/google_sign_in) rather than
assuming this code is stale — this is genuinely new API surface as of
early-to-mid 2026.

### Cloud Console setup needed before this runs

1. In the same Google Cloud project from the earlier OAuth verification
   discussion, create an **Android** OAuth client (package name + your
   debug/release SHA-1 fingerprint) and a **Web application** OAuth
   client.
2. Copy the Web client's ID into `AppConfig.googleWebClientId`.
3. The Android client doesn't need its ID pasted anywhere in code — it's
   resolved automatically via the package name/SHA-1 match.

### Security decisions worth knowing about

- Google's tokens are **not** persisted by this app at all — v7's
  underlying platform SDKs (Credential Manager on Android, Google
  Identity Services on Web) handle that themselves;
  `attemptLightweightAuthentication()` is what restores a session on
  cold start.
- The backend's refresh token **is** persisted, in `flutter_secure_storage`
  (Keystore/Keychain-backed), never in SharedPreferences. The short-lived
  access token is kept in memory only and re-derived on cold start.
- The `/auth` screen isn't gated by a redirect yet — both connections are
  optional-feeling by design right now ("Continue" always works). Real
  auth-gating (e.g. blocking Tasks until logged in) is deferred as its
  own focused piece of work, since it needs a Listenable bridged from
  Riverpod's streams into go_router's `redirect`.

## Before you run this for the first time

This repo only ever contained `lib/`, `pubspec.yaml`, and config files —
not a full `flutter create` output, which is also where the `android/`,
`web/`, `linux/`, `windows/` folders and `AndroidManifest.xml` come from.
Retrofit them once, before `flutter pub get`:

```
flutter create --org com.yourcompany.ephemeron .
```

Run inside the extracted project folder. This is the standard, documented
way to add platform folders to an existing Dart-only Flutter skeleton —
it won't overwrite `lib/` or your `pubspec.yaml` dependencies. (Worth
calling out explicitly now, since Step 2 is the first step that actually
needs `android/app/src/main/AndroidManifest.xml` to exist.)

## Step 2: Alarm/Notification engine

`features/alarms/` — light + medium presets only in this MVP step (see
`AlarmPreset`'s doc comment for why strong/constant are defined but not
implemented yet).

- **`AlarmScheduler`** (`data/alarm_scheduler.dart`) — the engine itself:
  channel setup, timezone resolution, offset-based scheduling
  (`scheduleAlarmsForOffsets`), and snooze/done handling in both the
  normal foreground callback and a background-isolate callback for when
  the app is fully terminated.
- **`AlarmRingScreen`** (`presentation/alarm_ring_screen.dart`) — the
  actual full-screen ringing UI, pushed directly through the shared
  `rootNavigatorKey` when a medium-preset alarm genuinely fires. Implements
  the 30-second auto-snooze-if-untouched behavior from the brainstorm.
- **`ReminderOffset`** (`domain/reminder_offset.dart`) — the "at time / 5
  min before / ... / custom" preset list, multi-selectable per entity.

### Required AndroidManifest.xml additions

flutter_local_notifications only declares the bare minimum itself —
add these once `android/app/src/main/AndroidManifest.xml` exists (see
above). Inside `<manifest>`, alongside any other `<uses-permission>` tags:

```xml
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
<uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
```

`USE_EXACT_ALARM` (rather than the user-granted `SCHEDULE_EXACT_ALARM`)
is used deliberately — no runtime prompt needed, but it requires your
Play Store listing to genuinely justify core alarm functionality, which
this app does. Reconsider if that stops being true.

Inside `<application>`:

```xml
<receiver android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
<receiver android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
  <intent-filter>
    <action android:name="android.intent.action.BOOT_COMPLETED"/>
    <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
    <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
  </intent-filter>
</receiver>
```

And on the main `<activity>` tag (the one extending `FlutterActivity`),
add these two attributes so the full-screen alarm can show over the lock
screen:

```xml
<activity android:showWhenLocked="true" android:turnScreenOn="true" ...>
```

Before a release build (not needed for `flutter run` in debug), follow
the plugin's ProGuard/R8 setup instructions in its README — release
builds strip things by default that the plugin needs kept.

### Where permission requests actually happen

`AlarmScheduler.requestPermissions()` is **not** called automatically at
startup — surfacing three permission dialogs before the user has done
anything is bad UX. Call it from wherever the user first sets a
reminder, or from a dedicated onboarding step (not built yet).

### Known limitation, stated plainly

If the user taps "Mark done" on a notification action button while the
app is fully closed, this cancels the remaining scheduled alarms for
that entity, but does **not** yet mark the actual task/habit complete in
the local database — that requires isolate-safe Drift writes, which
lands naturally once the Tasks (Step 3) and Habits (Step 6) repositories
exist to hook into `AlarmScheduler.actionEvents`. Opening the app after
tapping "done" this way will currently still show the task as pending.

## Step 3: Tasks/Lists core

`features/tasks/` — the central entity. Local Drift storage is the
source of truth; Google Tasks gets a best-effort mirror of the subset it
can actually hold.

- **`TaskRepository`** (`data/task_repository.dart`) — CRUD, list
  management (Inbox can't be deleted; deleting a list reassigns its
  tasks rather than cascading), tags, and the 6 smart lists (today/
  tomorrow/next 7 days/completed/trash/won't-do). Every create/update
  recomputes alarms (cancel-then-reschedule against Step 2's
  `AlarmScheduler`) and best-effort pushes to Google Tasks.
- **`GoogleTasksMirror`** (`data/google_tasks_mirror.dart`) — push-only
  (local → remote) for this MVP step. Pulling in edits made directly in
  Google's own Tasks app is a later phase — see the class's doc comment
  for why (a webhook-based pull would need a public server, which
  conflicts with the CASA-avoidance architecture; polling-based pull is
  the right way to add this later, just not built yet).
- **`TaskRecurrence`** (`domain/task_recurrence.dart`) — the "basic
  repeat" scope: daily, weekly-on-specific-weekdays, yearly. Completing a
  recurring task creates the next occurrence as a fresh row rather than
  mutating the completed one in place, so history stays intact.
- Real UI replacing the Step 0 placeholder: a list picker, task list
  with complete/pin/swipe-to-delete, and an add/edit sheet covering
  title/description/priority/due date/alarm+reminders. This is **not**
  the full rich Create-button quick-add flow from the brainstorm (audio,
  templates, shorthand parsing, convert-to-event) — that's its own
  focused future build item, kept out of Step 3 to keep this step
  reviewable.

### Two corrections to earlier steps, made now

- **`Lists` table would have generated a class literally named `List`**,
  colliding with `dart:core`'s `List<T>` — fixed via `@DataClassName
  ('TaskList')` in `tables.dart`. Harmless until a step actually
  generated and used the class, which this one is.
- **Schema bumped to v2** with a real migration (not just a
  `onCreate` rewrite) — `isDeleted`/`deletedAt` (Trash) and the three
  alarm-linkage columns are added via `onUpgrade`, modeling the pattern
  every future schema change should follow.

### Google auth scope change

`GoogleAuthRepository.getCalendarAccessToken()` (Step 1) is now a thin
wrapper around a new general `getAccessToken(List<String> scopes)` —
Tasks needs its own scope alongside Calendar's, and requesting both
together in one authorization round (done in `AuthScreen._signIn` now)
avoids prompting the user twice. Nothing that already called the old
method needs to change.

### Known limitation, stated plainly

Sync is one-directional. If the user edits a task's title directly in
Gmail's task pane or the Google Tasks mobile app, Ephemeron won't see
that change until pull sync exists. Fields Google can't store at all
(priority, tags, recurrence, exact due-time, deep subtasks) obviously
never round-trip either — this was flagged from the very first
architecture discussion and hasn't changed.

## Step 4: Calendar

`features/calendar/` — the one place this app's architecture inverts
compared to Tasks: Google Calendar itself is the source of truth here,
not a local mirror. There's no local Drift table for event data at all.

- **`CalendarRepository`** (`data/calendar_repository.dart`) — direct
  CRUD passthrough to `googleapis`'s `calendar/v3` client. Failures
  surface straight to the UI rather than being swallowed as best-effort
  — unlike `GoogleTasksMirror`, there's no local fallback to quietly
  fall back on if a call fails.
- **Event reminders piggyback on Google's own `reminders.overrides`
  field** instead of needing a parallel local table: every time events
  are fetched, `AlarmScheduler` reschedules local alarms for whatever
  minutes-before-start Google already has stored, always at
  `AlarmPreset.light`. This is a deliberate MVP scope cut — choosing
  light vs. medium per event would need a small local table mirroring
  what Tasks' `alarmPreset` column already does, not built yet since
  reminders work correctly without it.
- **`EventTags`** (new table, schema v3) — the local layer for custom
  tagging. Google Calendar's own `colorId` is a fixed 11-color palette
  (built into `GoogleEventColor`), not a custom tag system, so richer
  tagging/filtering needs this local join table keyed by the Google
  event ID, reusing the same `Tags` table Tasks already uses.
- **Views**: month grid (via the `table_calendar` package) with the
  selected day's agenda listed below it — covers 2 of the 6 views named
  in the original brainstorm (month + daily list) in one screen. Week,
  year, timeline, and custom-N-day views are explicitly deferred, same
  scope-cutting pattern as every other step so far.
- **Sync indicator** — the app bar's sync icon calls
  `ref.invalidate(monthEventsProvider(...))`, which is the entire "force
  sync" mechanism: Riverpod just refetches, no separate sync-state
  machinery needed since Google is already the source of truth.

### Why month-range fetching, not per-day

`monthEventsProvider` fetches a whole month at once, keyed by the
month's first day; `dayEventsProvider` derives a single day from
whatever month is already loaded rather than making its own request.
Tapping around within a visible month is instant; changing months
triggers exactly one new fetch.

### Known limitation, stated plainly

Recurring Google Calendar events are expanded into individual instances
by `singleEvents: true` — this means editing "this event" always edits
that specific instance, never the whole series. Editing an entire
recurring series (Google's own "this and following" / "all events" UI)
isn't exposed yet; for now, do that kind of edit in Google Calendar's own
app and let Ephemeron pick it up on next sync.

## Step 5: Create button / quick-add unification

`features/quick_add/` — the single global "+" from the original
brainstorm, replacing the separate per-screen FABs Steps 3 and 4 each
built (TasksScreen and CalendarScreen no longer have their own FAB —
`AppShell` hosts one, shown on Calendar/Tasks/Matrix per the brainstorm's
"Create button on task related sections" scope).

- **`QuickAddParser`** (`domain/quick_add_parser.dart`) — the
  `title #tag ~list -p4` shorthand. Priority is 1-indexed in the
  shorthand (`-p1`..`-p4`) to match the brainstorm's own example, mapped
  internally to this app's 0-3 scale (`-p4` → `priority: 3`, high).
- **`QuickAddSheet`** (`presentation/quick_add_sheet.dart`) — a
  Task/Event toggle over one shared title field with live shorthand
  parsing (detected tag/list/priority show as chips as you type).
  Referencing a tag or list that doesn't exist yet creates it, per the
  brainstorm ("if none is selected, create a new tag/list").

### Scope, stated plainly

This is **not** the full rich Create-button experience from the
brainstorm — no audio recording, templates, attachments, or full-screen
expand yet. Step 5's job was specifically the unification (one button,
one shared parser, Task vs. Event as a toggle rather than two disconnected
flows) — the richer input methods remain open future work, each a
reasonably self-contained addition on top of this sheet rather than a
rearchitecture of it.

Editing an existing task/event still opens the fuller `TaskFormSheet` /
`EventFormSheet` directly (tapping a list item) — the quick-add sheet is
create-only, matching how the brainstorm describes it as a fast-entry
point, not a full editor.

## Step 6: Habits

`features/habits/` — daily/weekly/interval frequency, binary or amount
goals, sections, and streak metrics. Depends on the Alarm engine
directly, more than Tasks or Calendar did — habit reminders needed a
genuinely different scheduling shape.

- **`HabitFrequency`** (`domain/habit_frequency.dart`) — daily (every day,
  or specific weekdays only), weekly (X times per week, not tied to
  specific days), interval (every N days from start). `isDueOn(date)` is
  the one method both "what shows today" and streak calculation lean on.
- **Two new `AlarmScheduler` methods**, not one: `scheduleRecurring`
  (genuinely OS-recurring via `matchDateTimeComponents` — daily and
  weekly-on-specific-weekdays habits get this, set once, fire forever, no
  app-side rescheduling) and `scheduleOneShotAt` (a single next-occurrence
  alarm for weekly-by-count and interval habits, which have no fixed
  weekday to peg a recurring alarm to). `HabitRepository
  .refreshOneShotAlarms()` — wired into app startup right after the
  alarm engine's own init — catches up the one-shot cases; the recurring
  ones never need this.
- **Streak calculation** (`HabitRepository._computeStreak` and
  `_computeWeeklyStreak`) — walks backward from today counting
  consecutive applicable-and-completed days, with today itself exempted
  from breaking a streak if not yet logged (so an in-progress day doesn't
  prematurely zero out what's actually still achievable). Weekly habits
  count whole weeks that hit their target, not individual days.
- **Metrics scope, stated plainly**: current streak, longest streak
  (a simplified longest-consecutive-run scan, not exhaustively
  weekly-aware), and a 7-day strip. The brainstorm's full month heatmap
  is explicitly Phase 2 — this is the "basic streak/progress circle"
  MVP cut, not the whole metrics feature.
- **No persisted per-section default alert time.** The brainstorm
  describes each section (morning/afternoon/night) having its own
  default alert setting — building that as a real, editable, persisted
  setting would need its own small table. What's here instead:
  `HabitSection.suggestedHour` pre-fills a sensible reminder time in the
  add-habit form based on the chosen section, as a one-time UI
  convenience, not a setting that later habits inherit changes from.
  Worth a proper settings table if you want the real version later.

### A bug caught during review, worth knowing about

A first draft of the daily-with-specific-weekdays alarm scheduling used
a per-weekday-munged entity ID (`'${habit.id}_$weekday'`) to keep
notification IDs distinct across weekdays. That was unnecessary —
`scheduleRecurring`'s own ID hash already factors in `weekday` — and
actively harmful: it would have broken any future lookup that tries to
map a fired alarm's payload back to the actual habit, since the ID in
the payload wouldn't match a real row. Fixed to use the real habit ID
throughout; only the notification ID (not the payload) needs to differ
per weekday.

## Step 7: Focus

`features/focus/` — Pomodoro/Stopwatch timer, optional link to a task or
habit, and the metrics rollups from the brainstorm. No schema migration
needed — Step 0's `FocusSessions` skeleton was already sufficient.

- **`FocusTimerController`** (`application/focus_timer_controller.dart`)
  — owns the live ticking `Timer`, wakelock, and ongoing notification
  together. Tracks a `_trueSessionStart` separately from the per-run
  `startedAt` specifically so a paused-and-resumed session still records
  its real original start time — a bug caught during review, see below.
- **Sessions under 5 minutes aren't stored at all** — matches the
  brainstorm's "focus sessions longer than 5min will be stored" literally
  (not "stored but excluded from metrics after the fact").
- **Habit-goal integration**: a session linked to a habit whose goal unit
  looks time-based (`goalUnit` containing "min" or "hour"/"hr", checked
  as a simple substring match since units are free text) adds its
  duration to that habit's today-log automatically. Anything else
  (pages, reps, ...) still links for the record but can't be meaningfully
  derived from a duration, so it doesn't move the goal needle — a
  heuristic, not a guarantee, worth knowing about if you use unusual
  goal-unit wording.
- **Ongoing notification, not a floating overlay** — reuses
  `AlarmScheduler`'s existing plugin instance with two new methods
  (`showOngoingNotification`/`cancelOngoingNotification`) using Android's
  `usesChronometer` field, so the OS renders the live "MM:SS" counter
  itself rather than the app re-posting the notification every few
  seconds. Same reasoning as the original brainstorm discussion: cheaper
  on battery, no `SYSTEM_ALERT_WINDOW` permission scrutiny.
- **Pomodoro is fixed at 25/5** for this MVP step — customizable
  durations are Phase 2.
- **Metrics scope**: today/this-week totals on the main screen, a
  month/year/all-time drill-down one tap away. This is the "basic
  metrics" MVP cut — no visual heatmap yet, just a plain per-day list.

### A real bug caught during review

The first draft computed a completed session's `startedAt` by subtracting
its active-elapsed duration from `DateTime.now()` — which drifts
whenever the session was paused at any point, since paused time isn't
part of "elapsed" but *is* part of wall-clock time. Fixed by tracking the
session's true first-start moment explicitly (`_trueSessionStart`, set
once per session, untouched by pause/resume) rather than trying to
reconstruct it after the fact.

### Known limitation, stated plainly

The ongoing notification keeps updating for as long as the app process
is alive, but this isn't backed by a true Android foreground service —
under sustained memory pressure while fully backgrounded for a long
time, the OS can still suspend the process earlier than a foreground-
service-backed app would. Making this fully bulletproof needs a
dedicated foreground service, which is real native Android work,
explicitly scoped out of this step rather than silently assumed to be
handled.

### Addendum: goal units became selectable, plus a per-log increment

Originally the goal unit was free text, which is also what forced
Step 7's habit-time integration into a fragile substring heuristic. Fixed
retroactively:

- **`HabitGoalUnit`** (`domain/habit_goal_unit.dart`) — a curated,
  selectable list (minutes, hours, ml, liters, glasses, km, miles, steps,
  pages, times, reps, calories) replacing the old free-text field in the
  form UI. A "Custom..." option still falls back to free text for
  anything not covered — the database column itself is still plain text,
  so this needed no schema change, only a UI change plus an exact-match
  path in `FocusRepository` (falling back to the old substring heuristic
  only for custom-typed units).
- **`logIncrement`** (new column, schema v5) — how much a single quick-
  log tap adds toward the goal (e.g. goal "2 hours" with increment 1 —
  two taps hits the goal; goal "2500 ml" with increment 200 — about
  twelve taps). Logging a habit is now a fast one-tap action
  (`HabitRepository.quickLogToday`) instead of typing the full running
  total every time; the original typed-amount dialog is still there as a
  long-press escape hatch for manual correction.

## Step 8: Countdown

`features/countdown/` — the cheapest step in the build order, and it
stayed that way: no new architecture, just composing pieces every
earlier step already built.

- **`CountdownStatus.compute`** (`domain/countdown_status.dart`) — the
  entire "days left / days since / age" calculation, pure and stateless.
  Yearly countdowns always compute a future occurrence (this year's date,
  or next year's if it already passed) — a recurring countdown is never
  "in the past" by definition.
- **Fixed default alerts** (3 days before + on the day, per the
  brainstorm) rather than the user-configurable offset/preset picker
  Tasks and Events have — deliberately not exposed as a setting in this
  MVP step, matching how the brainstorm describes it as a fixed default
  rather than a choice.
- **Yearly alarm rollover** reuses the exact pattern Habits' weekly/
  interval one-shot alarms established in Step 6: schedule against the
  next occurrence, and catch up via `refreshYearlyAlarms()` at startup
  once that occurrence has passed. Same underlying reason both times —
  there's no native OS "once a year" recurrence rule to peg a alarm to
  the way `matchDateTimeComponents` handles daily.
- **Template picker** (`presentation/countdown_template_picker.dart`) —
  Holiday/Anniversary/Birthday/Countdown, matching the brainstorm's
  Create-button variant for this section exactly. Type determines
  defaults (yearly, age support) but the underlying schema is one table,
  not four.
- **Schema**: one new column (`scheduledAlarmIds`, schema v6) — Step 0's
  `Countdowns` table skeleton needed nothing else.

## Step 9: Cross-platform + polish pass

No new feature — an audit pass across Steps 0–8 for cross-platform
correctness, plus closing a real gap: there was no Settings screen at
all until now, despite `AppSettings` (reduced motion, power-saving mode,
theme) existing since Step 0.

### Two real bugs found and fixed

- **`AlarmScheduler.requestPermissions()` would have crashed on Web.**
  `dart:io`'s `Platform.isAndroid` throws at runtime on web rather than
  returning false — this method checked it directly. Fixed by checking
  `kIsWeb` first so short-circuit evaluation never touches `Platform` on
  web at all. This is exactly the kind of bug that only shows up the
  first time you actually try the web target, which is the point of this
  step existing.
- **The entire alarm engine cannot function on Web, and wasn't guarding
  for it.** Browsers don't support scheduled or repeating notifications
  — not a bug, a platform limitation with no client-only fix (a real fix
  needs Web Push plus a server, which conflicts with this app's
  CASA-avoidance architecture). `scheduleAlarmsForOffsets`,
  `scheduleRecurring`, and `scheduleOneShotAt` now check a new
  `supportsScheduledAlarms` flag (`!kIsWeb`) and no-op cleanly instead of
  calling into a plugin method the browser can't fulfill. The Settings
  screen surfaces this plainly to web users rather than leaving reminders
  silently not firing with no explanation.

### New: Settings screen

Reachable from the "More" sheet (now always shown, not just when there
happen to be overflowed nav sections, since Settings lives there too).
Exposes theme mode, reduced motion, manual power-saving override, and —
new this step — live OS battery-saver detection via `battery_plus`,
feeding into the same `shouldReduceMotion` flag the manual toggles use.
Battery state is checked once at startup with a manual re-check button;
continuous monitoring via app-lifecycle events would be the natural next
step but is real additional scope, not bundled in here.

### Known gaps, stated plainly rather than silently left

- **Drift's web target needs a `sqlite3.wasm` asset** bundled and served
  correctly (plus OPFS generally wanting HTTPS) for the database to work
  in the browser at all — this is hosting/build configuration, not
  something fixable from application code, and hasn't been verified
  end-to-end here since there's no way to actually run `flutter build
  web` in this environment. Check `drift_flutter`'s current setup docs
  before shipping a web build.
- **`google_sign_in` web setup should be double-checked against the
  current package README** — some versions have required a meta tag in
  `web/index.html` in addition to the programmatic `clientId` passed to
  `initialize()`; this wasn't verified against a real running web build.
- **Linux and Windows desktop remain entirely unbuilt**, per the original
  priority ranking (Android max priority, Web important, Linux/Windows
  optional). Nothing in this pass changes that — it's Android+Web
  correctness only.
- **No continuous OS battery-saver monitoring** — only checked at
  startup and on manual refresh, not on every app resume.

## A note on package versions

`pubspec.yaml` uses `^` floor constraints on each dependency. Run
`flutter pub outdated` after step 4 to see what's actually latest and
`flutter pub upgrade` to move onto it — don't treat the committed version
numbers as exact/final, they're a known-good starting point.
