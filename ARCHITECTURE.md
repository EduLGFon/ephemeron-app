# Ephemeron — System Architecture & Feature Specification

> **Target Audience**: AI Models & Autonomous Coding Agents\
> **Purpose**: Exhaustive reference document describing Ephemeron's
> architecture, data models, feature implementations, routing, state management,
> design constraints, and future proposed features.

---

## 1. System Overview & Core Philosophy

**Ephemeron** is a high-performance, blazing fast, battery-efficient, extremely
lightweight cross-platform productivity suite combining calendar events, tasks,
habits, countdowns, focus timers, notes, and the Eisenhower matrix into a
unified experience.

### Key Architectural Principles

1. **Privacy-First & CASA-Avoidant**: Direct client-to-Google OAuth integration
   (`google_sign_in` + `googleapis`). User tokens and Google Calendar/Tasks data
   flow strictly between the client device and Google's servers without passing
   through any intermediary backend server.
2. **Dual Independent Auth Systems**:
   - **Google OAuth**: Manages Google Calendar (v3) and Google Tasks (v1) data
     directly from the client. Supports Android (Credential Manager / Google
     Identity), Web (GIS), and Desktop Linux/Windows/macOS (Loopback OAuth2 flow
     with secure credentials storage via `SafeSecureStorage`).
   - **Backend Auth**: Custom backend connection reserved exclusively for
     app-specific custom data (e.g. habits, focus logs, notes, countdowns)
     following a standard REST contract (`/auth/register`, `/auth/login`,
     `/auth/refresh`, `/auth/logout`).
3. **Offline-First Storage**: Local relational storage powered by **Drift**
   (SQLite). SQLite runs natively on Android/Linux/Windows/macOS/iOS, and via
   WebAssembly (WASM) / OPFS on Web.
4. **Battery, Performance & Resource Efficiency**:
   - `PowerSavingManager` features a 3-mode system (Auto/Always On/Always Off).
     In Auto mode, it monitors the system battery level, triggering a low-power
     state at <15% to disable non-essential animations, background sync, and
     visual effects.
   - **Boot Performance**: Synchronous settings hydration from SharedPreferences
     and parallel bootstrapping via `Future.wait` (`appBootstrapperProvider`)
     eliminate splash screens, achieving <1s time-to-interactive.
   - **Rendering Optimization**: Extensive use of `RepaintBoundary` for UI
     isolation, memoized `TextSpan` trees for Markdown syntax highlighting, and
     cached `ThemeData` to minimize rebuilds.
   - **High-Frequency State**: Rapidly updating state (e.g. Focus Timer ticks)
     uses `ValueNotifier<Duration>` instead of full Riverpod state to prevent
     widget tree churn.
   - Bundled local fonts (`Fraunces` and `Inter` in `assets/fonts/`) eliminate
     runtime network fetches.
   - Sync operations are battery-aware, halving their interval during
     power-saving mode.
   - Task/Habit/Countdown alarms & reminders use OS-native exact alarm APIs
     (`flutter_local_notifications`), executing independently of background
     polling even when the app is closed.
5. **Cross-Platform Priority**:
   - **Android**: Primary priority (exact alarms via `USE_EXACT_ALARM`,
     foreground service, native notification channel, Android 16 promoted
     ongoing live updates).
   - **Linux & Web**: Medium priority (Desktop audio stubs via
     `desktop_alarm_sound.dart`, desktop notifications via `local_notifier`,
     WASM SQLite engine).
   - **Windows & macOS**: Supported low-priority platforms.

---

## 2. Directory Structure & Layering Architecture

The codebase strictly follows a **Feature-First Clean Architecture** with
standardized layer separation:

```
lib/
├── core/                        # Global application foundation
│   ├── bootstrap/               # Parallel bootstrapping & startup hydration
│   ├── config/                  # App-wide configuration (OAuth IDs, API endpoints)
│   ├── network/                 # Custom HTTP clients (BearerHttpClient)
│   ├── routing/                 # GoRouter declaration & auth state redirection
│   ├── settings/                # SharedPreferences, Power Saving Manager, Session Restore
│   ├── theme/                   # Theme Engine, palettes, typography, color constants
│   ├── utils/                   # Developer loggers, secure storage wrappers
│   └── widgets/                 # Reusable cross-feature UI widgets
├── data/                        # Global local database
│   └── local/                   # Drift SQLite schema definitions and database DAO
├── features/                    # Modular feature implementations
│   ├── alarms/                  # Alarm scheduler, foreground ring engine, notifications, desktop audio
│   ├── auth/                    # Google & Backend authentication repositories (Android/Web/Desktop)
│   ├── calendar/                # Google Calendar sync, daily/multi-day timeline, month grid, device calendars
│   ├── countdown/               # Target date countdowns, age calculation & auto-recurring yearly alerts
│   ├── focus/                   # Pomodoro & Stopwatch focus timer engine, promoted Live Updates, metrics
│   ├── habits/                  # Daily/Weekly/Interval habit tracking, sections, quick logs & streak metrics
│   ├── matrix/                  # Eisenhower 2x2 priority matrix view
│   ├── notes/                   # Rich Markdown note editor, hierarchical folders & search filter
│   ├── quick_add/               # Natural language shorthand parser & unified creation modal
│   ├── settings/                # User preferences, appearance, haptics, calendar/account/sync configuration
│   ├── sync/                    # Background bidirectional sync service (calendar & tasks)
│   ├── tags/                    # Custom color-coded tagging engine, tag defaults & autocomplete
│   └── tasks/                   # Task management, Google Tasks mirror repository & smart lists
└── presentation/                # Shell layout & global UI screens
    ├── notes/                   # Markdown previewer, syntax highlighters & smart lists
    ├── shell/                   # Stateful bottom nav, customizable section switcher, and Quick Add pill
    └── widgets/                 # Shared modal dialogs, date/time config sheets & reusable components

packages/                        # In-repo platform override packages
├── device_calendar_plus_android # Local Android implementation override
├── flutter_timezone             # Cross-platform timezone resolution plugin
├── pasteboard                   # System clipboard interop package
└── wakelock_plus                # Screen wake lock management plugin
```

### Layer Responsibility Matrix

- **`domain/`**: Data models, enums, value objects, pure parsing rules (no
  Riverpod or UI dependencies).
- **`data/`**: Repositories, Drift database interactions, external API clients,
  platform stubs.
- **`application/`**: Riverpod `Notifier`/`AsyncNotifier` providers, background
  service managers, timer loops.
- **`presentation/`**: UI screens, modal bottom sheets, form widgets, custom
  renderers.

---

## 3. Database Schema (`lib/data/local/tables.dart`)

Drift manages the SQLite database (`AppDatabase` in
`lib/data/local/database.dart`). Below are the 13 defined tables:

| Table Name             | Primary Key              | Description & Special Logic                                                                                                                                                                                                                          |
| :--------------------- | :----------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Lists`                | `id` (UUID v4)           | Task lists (e.g. Inbox, Personal, Work). Includes `isInbox` flag and seed data.                                                                                                                                                                      |
| `Tags`                 | `id` (UUID v4)           | Custom color tags. Contains smart defaults for alarm presets (`defaultAlarmPreset`), colors (`defaultColorHex`), and linked note folders (`defaultNoteFolderId`).                                                                                    |
| `Tasks`                | `id` (UUID v4)           | Core task table. Best-effort mirror with Google Tasks via `googleTaskId`. Preserves local-only metadata (priority 0-3, `recurrenceRule`, `durationMinutes`, pins, `isWontDo`, `isDeleted` soft-delete, alarm settings, `parentTaskId` for subtasks). |
| `TaskTags`             | `{taskId, tagId}`        | Junction table linking tasks to custom tags.                                                                                                                                                                                                         |
| `EventTags`            | `{googleEventId, tagId}` | Junction table linking Google Calendar events to local custom tags (overcomes Google's fixed 11-color palette limit).                                                                                                                                |
| `Habits`               | `id` (UUID v4)           | Habit definitions (daily, weekly, interval). Supports binary or amount goals, curated goal units, single-tap `logIncrement`, sections (morning/afternoon/night/other), and reminder times.                                                           |
| `HabitLogs`            | `id` (UUID v4)           | Daily habit execution records. Unique constraint on `{habitId, date}` enabling upsert semantics.                                                                                                                                                     |
| `FocusSessions`        | `id` (UUID v4)           | Logged focus sessions (Pomodoro or Stopwatch). Optional foreign keys to `linkedTaskId` and `linkedHabitId`. Sessions < 5m are discarded.                                                                                                             |
| `Countdowns`           | `id` (UUID v4)           | Target date countdowns (holidays, birthdays, anniversaries, custom). Features `isYearly` auto-roll, `showAge` calculation, and automated alerts.                                                                                                     |
| `NoteFolders`          | `id` (UUID v4)           | Hierarchical folder structure for notes (`parentFolderId`).                                                                                                                                                                                          |
| `Notes`                | `id` (UUID v4)           | Markdown notes. Optional linkage to `folderId`, `eventId`, or `linkedCalendarId`.                                                                                                                                                                    |
| `CachedCalendarEvents` | `{id, calendarId}`       | Offline local cache of Google Calendar events including recurrence rules, video conference links, attendees, and RSVP status.                                                                                                                        |
| `CustomSmartLists`     | `id` (UUID v4)           | Custom task views filtered by priority, date range, tags, and completion state.                                                                                                                                                                      |

---

## 4. Implemented Feature Specifications & Technical Mechanics

### 1. Unified Task & Event Management (`features/tasks`, `features/calendar`)

- **Google Tasks Mirror & Sync**:
  - Bidirectional sync between local Drift `Tasks` table and Google Tasks API v1
    (`GoogleTasksMirror`, `syncTasksWithRemote`).
  - Synced fields: Title, description/notes, due date, completion status,
    single-level subtasks (`parentTaskId`).
  - Local-only fields: Priority scale 0-3 (0 = None, 1 = Low, 2 = Medium, 3 =
    High), recurrence rules (JSON-encoded `TaskRecurrence`), tags, duration, pin
    status, soft deletion ("Trash"), "Won't Do" status (`isWontDo`), alarm
    presets and reminder offsets.
  - Smart Lists: Inbox, Today, Tomorrow, Next 7 Days, High Priority, Scheduled,
    Completed, Trash, and Won't Do.
  - Sorting & Reordering: Sort by priority, due date, last completed first, or
    manual drag-and-drop reordering via `ReorderableDelayedDragStartListener`.
- **Calendar Engine**:
  - **Views**: Daily Timeline (`CalendarDailyTimelineView`), Multi-Day Timeline
    (`CalendarMultiDayTimelineView`: 3 Days, 4 Days, Week), Month Grid
    (`CalendarMonthGridView` using `table_calendar`).
  - **Sources**: Direct Google Calendar API v3 fetching with local caching
    (`CachedCalendarEvents`) + native local device calendar read/write/delete
    (`DeviceCalendarRepository`). Supports viewing events from all Google
    account calendars concurrently with per-calendar visibility toggles.
  - **Timeline Drag & Interactions**:
    - 15-minute grid snapping with tactile haptic feedback during event drag.
    - Vertical drag-and-drop to adjust start time and duration.
    - Horizontal event dragging across day columns on multi-day views.
    - Dynamic pinch-to-zoom, Ctrl+Scroll, and keyboard shortcuts (`+` / `-`) to
      scale hour height dynamically.
    - Day-by-day horizontal swipe navigation with live sliding page previews and
      detached time column/header.
    - Double-click to navigate to Day View; Escape shortcut to return to Month
      View.
    - Red current time indicator line auto-scrolled comfortably into viewport.
  - **Cross-Feature Calendar Overlays**:
    - Scheduled tasks plotted on daily/multi-day timelines and agenda with
      interactive completion checkmarks.
    - Habit reminders plotted on calendar timeline at their scheduled hours with
      interactive checkmarks for one-tap logging.
  - **Rich Event Capabilities**:
    - Nested contained events inside larger event bubbles; overlap column layout
      distribution.
    - Google Meet video conference link detection and joining.
    - Invitees/attendees list with RSVP status feedback and confirmation before
      sending email notifications.
    - Recurrence handling and deletion dialogs ("this instance" vs "all
      instances").
  - **Persistence**: Remembers active calendar date, vertical timeline scroll
    offset, and last selected calendar view across restarts.

### 2. Habit Tracking (`features/habits`)

- **Frequencies**: Daily (every day or specific weekdays), Weekly ($X$ times per
  week), Interval (every $N$ days from start).
- **Sections**: Morning, Afternoon, Night, Other (with suggested reminder hours
  based on section).
- **Goal Types**:
  - **Binary**: Done or not done.
  - **Amount**: Target quantity with curated units (`minutes`, `hours`, `ml`,
    `liters`, `glasses`, `km`, `miles`, `steps`, `pages`, `times`, `reps`,
    `calories`, `custom`).
- **Fast Logging**: Single-tap quick log (`logIncrement`) and long-press manual
  correction dialog.
- **Streak Metrics**: Calculates current streak, best streak, 7-day strip,
  completion rates, and historical logs (`HabitMetrics`), with in-progress
  current day protection.
- **Reminders**: Recurring OS alarms for daily/weekday habits; one-shot rollover
  alarms for weekly/interval habits (`refreshOneShotAlarms`).
- **Calendar Timeline Integration**: Habit reminders plotted on calendar
  timeline with interactive checkmarks for one-tap logging.

### 3. Eisenhower Matrix (`features/matrix`)

- Categorizes tasks into four quadrant views based on **Urgency** and
  **Importance**:
  - **Q1 (Urgent & Important)**: Do First.
  - **Q2 (Not Urgent & Important)**: Schedule.
  - **Q3 (Urgent & Not Important)**: Delegate / Quick Win.
  - **Q4 (Not Urgent & Not Important)**: Eliminate.
- Due dates displayed directly on tasks in all quadrants.
- Tappable completion checkmarks in grid overview.
- Drag-and-drop or tap-to-move quadrant re-assignment.
- Show/hide completed tasks toggle.

### 4. Focus Timer (`features/focus`)

- **Modes**:
  - **Pomodoro**: Structured intervals (25m work, 5m break).
  - **Stopwatch**: Continuous count-up timer.
- **High-Frequency Performance**: Timer ticks update via
  `ValueNotifier<Duration>` to isolate rendering from the Riverpod widget tree.
- **Live Updates & Background Execution**:
  - Android 16 Live Update pill notification via MethodChannel promoted ongoing
    channel (`promoted_notification_channel.dart`).
  - Android Foreground Service integration (`AlarmForegroundService`) to prevent
    background process suspension during active focus work.
  - Screen wake lock management via `wakelock_plus`.
- **Entity Linkage**: Focus sessions can be attached to active tasks or habits.
  Linking to a time-based habit automatically increments the habit's today
  progress.
- **Session Threshold & Precision**: Sessions under 5 minutes are discarded to
  prevent clutter. Tracks `_trueSessionStart` independently of pause/resume
  cycles.
- **Metrics**: Today/This Week main metrics summary, with Month/Year/All-time
  drill-down screens (`FocusMonthScreen`).

### 5. Countdowns (`features/countdown`)

- Tracks exact days and hours remaining until target dates, or days elapsed for
  past events.
- Categories & Templates: Holiday, Anniversary, Birthday, Custom.
- **Yearly Auto-Roll**: `isYearly` automatically advances target dates to the
  next calendar year once passed.
- **Age Calculation**: Computes turning age for birthdays and anniversary years
  (`showAge`).
- **Automated Alarms**: Schedules native OS alerts for 3 days before and on the
  day of the event; catches up yearly alarms on app startup
  (`refreshYearlyAlarms`).

### 6. Markdown Notes & Smart Editor (`presentation/notes`, `features/notes`)

- Full Markdown document editing with custom `MarkdownSyntaxHighlighter` and
  live rendered `MarkdownPreviewWithLists`.
- **Hierarchical Folders**: Nested directory structure (`NoteFolders`,
  `parentFolderId`) with breadcrumbs navigation.
- **Drag-and-Drop Organization**: Drag notes into folder breadcrumbs to
  organize.
- **Smart Formatting**: Auto-continues bullet points (`-`, `*`), numbered lists
  (`1.`), and checkbox syntax (`[ ]`, `[x]`).
- **Interactive Checkboxes**: Tapping checkboxes directly in editor or preview
  mode updates the raw Markdown string without breaking document formatting.
- **List Reordering**: In-editor tap-to-move list item reordering arrows (with
  toggle).
- **Search & Filtering**: Search bar filtering notes by title, tag, content, and
  folder.
- **Bidirectional Note ↔ Calendar Event Linking**: Notes link to calendar events
  (`linkedCalendarId`, event link chips) with bidirectional navigation.
- **Local Attachments & Auto-Draft**: Local image attachment support; automatic
  draft buffer preservation and clean discard.

### 7. Native Alarm & Notification Engine (`features/alarms`)

- **Multi-Platform Execution**:
  - **Android**: Exact OS alarms (`USE_EXACT_ALARM`), full-screen overlay
    intents (`USE_FULL_SCREEN_INTENT`), and foreground service execution.
  - **Desktop (Linux/Windows)**: Cross-platform notifications via
    `local_notifier`, and native system audio playback
    (`desktop_alarm_sound.dart`).
  - **Web**: Gracefully disabled or falling back cleanly where scheduled
    background notifications are unsupported.
- **Alarm Presets**:
  - `light`: Standard sound / heads-up notification.
  - `medium`: Full-screen ring overlay (`AlarmRingScreen`) with a 30-second
    auto-snooze if untouched.
- **Configurable Reminders**: Flexible list of minute offsets relative to due
  dates/times (`ReminderOffset`).
- **Adjustable Snooze**: Snooze duration adjustable with `+`/`-` buttons between
  1 and 60 minutes (default 5m).
- **Dynamic Permission Requests**: Checks and requests notification, exact
  alarm, and overlay permissions dynamically when setting reminders.
- **Audio & Visual Customization**: Custom short/long alarm audio paths and
  background settings.

### 8. Quick Add Shorthand & Unified Creation Sheet (`features/quick_add`)

- **Floating Quick Add Pill**: Expandable floating pill attached dynamically
  above the software keyboard with context-aware action buttons.
- **Natural Shorthand Parser (`QuickAddParser`)**:
  - Example: `Submit quarterly report #work ~ProjectX -p3`
  - Parses: Title (`Submit quarterly report`), Tag (`work`), List (`ProjectX`),
    Priority (`-p3` maps to internal priority 2 = Medium).
  - Automatically creates referenced tags or lists that do not yet exist.
- **Unified Creation Sheet (`UnifiedCreationSheet`)**:
  - Target switcher: Instant switching between **Task**, **Event**, **Habit**,
    **Countdown**, and **Note**.
  - Advanced configuration per target:
    - Task: List, due date/time, duration, priority, tag, alarm preset,
      reminders, recurrence.
    - Event: Calendar selection, start/end date-time, Google Meet conferencing,
      attendees/guests, tags, reminders, recurrence rule.
    - Habit: Section, frequency, goal type, goal unit, log increment, reminder
      time.
    - Countdown: Target date, template type, yearly auto-roll, show age toggle.
    - Note: Folder selection, markdown editor, tag, linked calendar event.
  - Custom `DateTimeConfigSheet`: Generic date, time, duration picker with
    all-day toggle.
  - Discard confirmation dialog when closing dirty form sheets.

### 9. Background Synchronization Service (`features/sync`)

- Periodic background sync timer (default 30m, battery-aware doubling to 60m in
  power-saving mode).
- Manual sync trigger via status-reactive interactive calendar title.
- Parallel remote synchronization: Google Calendar event range fetching (past 1
  month to future 3 months) cached to `CachedCalendarEvents`, and Google Tasks
  bidirectional sync (`syncTasksWithRemote`).
- Device calendar cache invalidation upon sync.
- Immediate sync trigger on Google Sign-In.

### 10. Tagging & Category Engine (`features/tags`)

- Global color-coded tagging engine linking tasks (`TaskTags`) and calendar
  events (`EventTags`).
- Autocomplete `#tag` suggestions in form fields.
- **Smart Tag Defaults**: Predefined default alarm presets
  (`defaultAlarmPreset`), default event colors (`defaultColorHex`), and default
  note folders (`defaultNoteFolderId`) automatically populated on tag selection.

### 11. Application Settings & Preferences (`features/settings`, `core/settings`)

- **Appearance**: 4 dynamic palettes (`Obsidian Glass`, `Aurora`,
  `Minimalist Silk`, `Pure AMOLED`) + custom primary color picker, dark/light
  mode.
- **Tactile & Animations**: Haptic feedback toggle, soft grid snap animation
  toggle, reduced motion toggle.
- **Calendar Preferences**: Default view, first day of week, 24-hour time
  format, show/hide declining events, calendar visibility toggles.
- **Desktop OAuth Credentials**: Secure loopback client ID & client secret entry
  with `SafeSecureStorage`.
- **Navigation Bar Customization**: User-selectable 4 primary bottom navigation
  tabs with overflow drawer; saved to `SharedPreferences`.
- **Session Restore**: Preserves active navigation branch, active calendar date,
  timeline scroll position, and open modal sheets across app restarts.

---

## 5. Navigation & State Management Architecture

### Routing System (`lib/core/routing/app_router.dart`)

Built with `GoRouter` using `StatefulShellRoute`. Heavy screens have been
decomposed into lightweight, lazy-loaded component widgets (e.g.,
`CustomScrollView` with slivers for complex layouts) to minimize memory
footprint when switching tabs.

```
/auth (if signed out) -> /calendar (default landing)
                                 ├── /tasks
                                 ├── /matrix
                                 ├── /habits
                                 ├── /countdown
                                 ├── /focus
                                 └── /notes
```

### Customizable Shell Navigation (`lib/presentation/shell/app_shell.dart`)

- Users can customize which **4 features** appear on the primary bottom
  navigation bar.
- Unpinned features are accessible via the "More" overflow drawer.
- Selected navigation layout persists across app launches via
  `SharedPreferences`.

### Theme Engine & Design System (`lib/core/theme`)

- **Dynamic Palettes**: Supports 4 built-in palettes (`Obsidian Glass`,
  `Aurora`, `Minimalist Silk`, `Pure AMOLED`) via `ThemeEngineProvider`, plus
  user-defined custom primary colors.
- **Custom Typography**: Bundles `Fraunces` (serif accent) and `Inter`
  (sans-serif UI) locally.
- **Power Saving Integration**: When `PowerSavingManager` detects system battery
  saver mode or battery drops below 15% (in Auto mode), animations, mesh
  gradients, and background sync are automatically disabled or throttled.

---

## 6. Proposed Features & Future Roadmap (Phase 2+)

Below is the exhaustive catalog of proposed features and future enhancements
scoped across the application modules:

### 1. Advanced Alarm Engine

- **Strong Preset**: High-priority full-screen alert with prolonged siren sound,
  aggressive vibration patterns, and repeated notification escalation.
- **Constant Preset**: Continuous ringing up to 10 minutes that persists across
  device lock screens until dismissed via an interactive challenge (e.g. math
  puzzle, step counter, or checkbox sequence).
- **Per-Event Custom Alarm Preset**: Local join table enabling Google Calendar
  events to configure individual alarm presets (`light`, `medium`, `strong`,
  `constant`) beyond Google's default notification channels.

### 2. Focus Timer & Metrics

- **Customizable Intervals**: User-configurable work durations (15 to 90
  minutes) and break durations (3 to 30 minutes) for Pomodoro mode.
- **Break-Time Audio Alerts**: Dedicated alert sound and notifications when
  transitioning between work and break phases.
- **Visual Activity Heatmap**: GitHub-style visual contribution heatmap
  displaying focused hours across months and years.

### 3. Habit Tracking

- **Monthly Habit Heatmap**: Full-month and annual calendar contribution
  heatmaps showing daily completion consistency.
- **Per-Section Default Alert Times**: User-configurable persistent default
  reminder times for Morning, Afternoon, and Night sections.

### 4. Tasks, Lists & Smart Filters

- **Custom Smart Lists UI Query Builder**: Full interface for creating
  user-defined saved filters backed by the existing `CustomSmartLists` Drift
  table schema (dynamic filtering by minimum priority, due date ranges, custom
  tags, and completion state).
- **Google Tasks Deep Synchronization**: Background polling for remote task list
  creation/deletion and multi-list synchronization.

### 5. Calendar & Recurrence

- **Recurring Series Editing**: Full Google Calendar recurring series editing
  capabilities ("edit this instance only" vs "edit all upcoming events in
  series").

### 6. Quick Add Shorthand & Multi-modal Input

- **Natural Language Date & Time Parsing**: Expanded shorthand parser supporting
  date syntax (`@today`, `@tomorrow`, `@friday`, `@25/12`) and time syntax
  (`!2pm`, `!14:00`, `!morning`).
- **Voice Audio Dictation**: One-tap voice recording button with speech-to-text
  NLP conversion into structured tasks/events.
- **Creation Templates**: Reusable templates for recurring projects and quick
  checklists.
- **File Attachments**: Quick attachment picker for documents and images in
  tasks and notes.

### 7. Backend Cloud Synchronization

- **Custom App Data Sync**: Full end-to-end cloud synchronization of
  app-specific data (habits, habit logs, focus sessions, notes, countdowns)
  against `HttpBackendAuthRepository` via `/auth/*` and REST data endpoints.

---

## 7. Development & Testing Requirements

1. **Static Analysis**: All code changes must strictly pass `flutter analyze`
   without warnings or errors.
2. **Local Fonts**: `Fraunces` and `Inter` fonts are bundled locally in
   `assets/fonts/` (specified in `pubspec.yaml`).
3. **Drift Code Generation**: Modifications to `lib/data/local/tables.dart`
   require running `dart run build_runner build --delete-conflicting-outputs` to
   regenerate `database.g.dart`.
