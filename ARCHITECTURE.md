# Ephemeron — System Architecture & Feature Specification

> **Target Audience**: AI Models & Autonomous Coding Agents  
> **Purpose**: Exhaustive reference document describing Ephemeron's architecture, data models, feature implementations, routing, state management, and design constraints.

---

## 1. System Overview & Core Philosophy

**Ephemeron** is a high-performance, battery-efficient, cross-platform productivity suite combining calendar events, tasks, habits, countdowns, focus timers, notes, and the Eisenhower matrix into a unified experience.

### Key Architectural Principles
1. **Privacy-First & CASA-Avoidant**: Direct client-to-Google OAuth integration (`google_sign_in` + `googleapis`). User tokens and Google Calendar/Tasks data flow strictly between the client device and Google's servers without passing through any intermediary backend server.
2. **Dual Independent Auth Systems**:
   - **Google OAuth**: Manages Google Calendar (v3) and Google Tasks (v1) data direct from client.
   - **Backend Auth**: Custom backend connection reserved exclusively for app-specific custom data (e.g. habits, focus logs).
3. **Offline-First Storage**: Local relational storage powered by **Drift** (SQLite). SQLite runs natively on Android/Linux/Windows/macOS/iOS, and via WebAssembly (WASM) / OPFS on Web.
4. **Battery & Resource Efficiency**:
   - `PowerSavingManager` monitors device power-saving mode (`battery_plus`) to automatically disable non-essential animations and blur effects.
   - Bundled local fonts (`Fraunces` and `Inter` in `assets/fonts/`) eliminate runtime network fetches.
   - Sync operations use a lightweight periodic Dart timer while the app is open (configured via user settings).
   - Task/Habit/Countdown alarms & reminders use OS-native exact alarm APIs (`flutter_local_notifications`), executing independently of background polling even when the app is closed.
5. **Cross-Platform Priority**:
   - **Android**: Primary priority (exact alarms via `USE_EXACT_ALARM`, foreground service, native notification channel).
   - **Linux & Web**: Medium priority (Desktop audio stubs, WASM SQLite engine).
   - **Windows & macOS**: Supported low-priority platforms.

---

## 2. Directory Structure & Layering Architecture

The codebase strictly follows a **Feature-First Clean Architecture** with standardized layer separation:

```
lib/
├── core/                        # Global application foundation
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
│   ├── alarms/                  # Alarm scheduler, foreground ring engine, notifications
│   ├── auth/                    # Google & Backend authentication repositories
│   ├── calendar/                # Google Calendar sync, daily/multi-day timeline, month grid
│   ├── countdown/               # Target date countdowns & auto-recurring yearly alerts
│   ├── focus/                   # Pomodoro & Stopwatch focus timer engine
│   ├── habits/                  # Daily/Weekly/Interval habit tracking & metrics
│   ├── matrix/                  # Eisenhower 2x2 priority matrix view
│   ├── notes/                   # Rich Markdown note editor & hierarchical folders
│   ├── quick_add/               # Natural language shorthand parser & creation modal
│   ├── settings/                # User preferences & navigation section configuration
│   ├── sync/                    # Background bidirectional sync service
│   ├── tags/                    # Custom color-coded tagging engine & autocomplete
│   └── tasks/                   # Task management & Google Tasks mirror repository
└── presentation/                # Shell layout & global UI screens
    ├── matrix/                  # Matrix presentation components
    ├── notes/                   # Markdown previewer & syntax highlighters
    ├── shell/                   # Stateful bottom nav & customizable section switcher
    ├── splash/                  # Startup splash & auth initialization loader
    └── widgets/                 # Shared modal dialogs & glassmorphic wrappers

packages/                        # In-repo platform override packages
├── device_calendar_plus_android # Local Android implementation override
├── flutter_timezone             # Cross-platform timezone resolution plugin
├── pasteboard                   # System clipboard interop package
└── wakelock_plus                # Screen wake lock management plugin
```

### Layer Responsibility Matrix
- **`domain/`**: Data models, enums, value objects, pure parsing rules (no Riverpod or UI dependencies).
- **`data/`**: Repositories, Drift database interactions, external API clients, platform stubs.
- **`application/`**: Riverpod `Notifier`/`AsyncNotifier` providers, background service managers, timer loops.
- **`presentation/`**: UI screens, modal bottom sheets, form widgets, custom renderers.

---

## 3. Database Schema (`lib/data/local/tables.dart`)

Drift manages the SQLite database (`AppDatabase` in `lib/data/local/database.dart`). Below are the 13 defined tables:

| Table Name | Primary Key | Description & Special Logic |
| :--- | :--- | :--- |
| `Lists` | `id` (UUID v4) | Task lists (e.g. Inbox, Personal, Work). Includes `isInbox` flag and seed data. |
| `Tags` | `id` (UUID v4) | Custom color tags. Contains defaults for alarm presets, colors, and linked note folders. |
| `Tasks` | `id` (UUID v4) | Core task table. Best-effort mirror with Google Tasks via `googleTaskId`. Preserves local-only metadata (priority 0-3, `recurrenceRule`, duration, pins, `isWontDo`, `isDeleted` soft-delete, alarm settings). |
| `TaskTags` | `{taskId, tagId}` | Junction table linking tasks to custom tags. |
| `EventTags` | `{googleEventId, tagId}` | Junction table linking Google Calendar events to local custom tags (overcomes Google's fixed 11-color palette limit). |
| `Habits` | `id` (UUID v4) | Habit definitions (daily, weekly, interval). Supports binary or amount goals, log increments, and reminder times. |
| `HabitLogs` | `id` (UUID v4) | Daily habit execution records. Unique constraint on `{habitId, date}` enabling upsert semantics. |
| `FocusSessions` | `id` (UUID v4) | Logged focus sessions (Pomodoro or Stopwatch). Optional foreign keys to `linkedTaskId` and `linkedHabitId`. |
| `Countdowns` | `id` (UUID v4) | Target date countdowns (holidays, birthdays). Features `isYearly` auto-roll and `showAge` calculation. |
| `NoteFolders` | `id` (UUID v4) | Hierarchical folder structure for notes (`parentFolderId`). |
| `Notes` | `id` (UUID v4) | Markdown notes. Optional linkage to `folderId`, `eventId`, or `linkedCalendarId`. |
| `CachedCalendarEvents` | `{id, calendarId}` | Offline local cache of Google Calendar events including recurrence rules, video conference links, and attendees. |
| `CustomSmartLists` | `id` (UUID v4) | Custom task views filtered by priority, date range, tags, and completion state. |

---

## 4. Feature Specifications & How They Work

### 1. Unified Task & Event Management (`features/tasks`, `features/calendar`)
- **Google Tasks Mirror**: Bidirectional sync between local Drift `Tasks` table and Google Tasks API v1 (`GoogleTasksMirror`).
  - Synced fields: Title, description, due date, completion status, single-level subtasks (`parentTaskId`).
  - Local-only fields: Priority scale 0-3 (0 = None, 1 = Low, 2 = Medium, 3 = High), recurrence rules (JSON-encoded TaskRecurrence), tags, duration, pin status, soft deletion ("Trash"), alarm presets.
- **Calendar Engine**:
  - Views: Daily Timeline (`CalendarDailyTimelineView`), Multi-Day Timeline (`CalendarMultiDayTimelineView`), Month Grid (`CalendarMonthGridView` using `table_calendar`).
  - Sources: Direct Google Calendar API v3 fetching + optional native device calendar read (`DeviceCalendarRepository`).
  - Local Tagging: `EventTags` links Google Event IDs to local custom tags for rich visual categorization.

### 2. Habit Tracking (`features/habits`)
- **Frequencies**: Daily (all days or specific weekdays), Weekly ($X$ times per week), Interval (every $N$ days).
- **Goal Types**:
  - **Binary**: Done or not done.
  - **Amount**: Target quantity (e.g. 2000 ml water, 30 pages reading) with configurable single-tap `logIncrement`.
- **Metrics**: Computes current streak, best streak, completion rates, and historical logs (`HabitMetrics`).

### 3. Eisenhower Matrix (`features/matrix`)
- Categorizes tasks into four quadrant views based on **Urgency** and **Importance**:
  - **Q1 (Urgent & Important)**: Do First.
  - **Q2 (Not Urgent & Important)**: Schedule.
  - **Q3 (Urgent & Not Important)**: Delegate / Quick Win.
  - **Q4 (Not Urgent & Not Important)**: Eliminate.
- Drag-and-drop or tap-to-move quadrant re-assignment.

### 4. Focus Timer (`features/focus`)
- **Modes**:
  - **Pomodoro**: Fixed intervals for MVP (25m work, 5m break). Custom intervals are planned for Phase 2.
  - **Stopwatch**: Continuous count-up timer.
- **Task & Habit Linkage**: Focus timer can be attached to active tasks or habits to log exact focused effort directly to `FocusSessions`.
- **Wakelock Integration**: Utilizes `wakelock_plus` to prevent screen sleep during active focus work.

### 5. Countdowns (`features/countdown`)
- Tracks exact days/hours remaining until target dates.
- Categories: Holiday, Anniversary, Birthday, Custom.
- **Yearly Auto-Roll**: `isYearly` automatically advances target dates to the next calendar year once passed.
- **Age Calculation**: Computes turning age for birthdays and anniversary years.
- **Automated Alarms**: Automatically schedules native OS alerts for 3 days before and on the day of the event.

### 6. Markdown Notes & Smart Editor (`presentation/notes`, `features/notes`)
- Full Markdown document editing with custom `MarkdownSyntaxHighlighter` and live rendered `MarkdownPreviewWithLists`.
- **Smart Formatting**: Auto-continues bullet points (`- `, `* `), numbered lists (`1. `), and checkbox syntax (`[ ]`, `[x]`).
- **Real-Time Checkbox Toggling**: Tapping checkboxes directly in preview mode updates the underlying Markdown raw string without breaking document structure.

### 7. Native Alarm & Notification Engine (`features/alarms`)
- Powered by `flutter_local_notifications` and exact OS alarms (`USE_EXACT_ALARM`).
- **Alarm Presets**: Light, Medium, Strong, Constant (`AlarmPreset`). Note: `light` (standard sound/heads-up) and `medium` (full-screen overlay) are fully active in MVP; `strong` and `constant` are reserved for Phase 2.
- **Reminder Offsets**: Flexible list of minute offsets relative to due dates/times (`ReminderOffset`).
- **Full-Screen Ring UI**: `AlarmRingScreen` launches full-screen alerts on Android with an adjustable Snooze duration (1-60 minutes, default 5m) and Mark Done actions.

### 8. Quick Add Shorthand (`features/quick_add`)
- `QuickAddParser` parses natural shorthand input strings:
  - Example: `Submit quarterly report #work ~ProjectX -p3`
  - Parses: Title (`Submit quarterly report`), Tag (`work`), List (`ProjectX`), Priority (`-p3` maps to internal priority 2 = Medium). Note: Date (`@`) and time (`!`) shorthand parsing are not supported in the current parser version.
- `UnifiedCreationSheet`: Floating action modal allowing instant creation of Tasks, Events, Habits, Countdowns, or Notes, with full date/time picker support when switching targets.

---

## 5. Navigation & State Management Architecture

### Routing System (`lib/core/routing/app_router.dart`)
Built with `GoRouter` using `StatefulShellRoute.indexedStack`. Keeps per-tab navigation states preserved in memory across tab switches.

```
/splash -> /auth (if signed out) -> /calendar (default landing)
                                 ├── /tasks
                                 ├── /matrix
                                 ├── /habits
                                 ├── /countdown
                                 ├── /focus
                                 └── /notes
```

### Customizable Shell Navigation (`lib/presentation/shell/app_shell.dart`)
- Users can customize which **4 features** appear on the primary bottom navigation bar.
- Unpinned features are accessible via the "More" overflow drawer.
- Selected navigation layout persists across app launches via `SharedPreferences`.

### Theme Engine & Design System (`lib/core/theme`)
- **Dynamic Palettes**: Supports 4 built-in palettes (`Obsidian Glass`, `Aurora`, `Minimalist Silk`, `Pure AMOLED`) via `ThemeEngineProvider`.
- **Custom Typography**: Bundles `Fraunces` (serif accent) and `Inter` (sans-serif UI) locally.
- **Power Saving Integration**: When `PowerSavingManager` detects system battery saver mode, mesh gradients and non-essential UI animations are automatically disabled.

---

## 6. Development & Testing Requirements

1. **Static Analysis**: All code changes must strictly pass `flutter analyze` without warnings or errors.
2. **Local Fonts**: `Fraunces` and `Inter` fonts are bundled locally in `assets/fonts/` (specified in `pubspec.yaml`).
3. **Drift Code Generation**: Modifications to `lib/data/local/tables.dart` require running `dart run build_runner build --delete-conflicting-outputs` to regenerate `database.g.dart`.
