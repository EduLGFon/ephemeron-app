# Ephemeron: Complete Implementation Plan

Target: Flutter (Android first, then iOS, Web, Linux, macOS, Windows). Goal: every feature in the requirements list, built blazing fast, tiny, and near zero battery cost, plus the commonly forgotten calendar and task behaviors users expect.

## 0. How to use this document

- Build in the phase order of section 14. Each phase ends with acceptance criteria and must be shippable.
- Rules marked **MUST** are non-negotiable. Rules marked **SHOULD** can be deferred to a later phase.
- One change per commit, Conventional Commits, tests with every domain change.
- Anything not specified here: choose the option with less CPU, RAM, battery and network use.

## 1. Principles and budgets

Same principles as Pontual: fast, light, unstable-network tolerant, secure, LGPD-compliant.

| Area | Budget (mid-range Android, 2021 class) |
| --- | --- |
| Cold start to first interactive frame | under 600 ms (target 400 ms) |
| Warm start | under 200 ms |
| Frame time | 60/90/120 fps, no frame over 16 ms in lists, month grid, timeline |
| Idle RAM (foreground) | under 150 MB |
| Background CPU | zero when idle. No timers, no polling, no wakelocks outside focus |
| Battery | under 1% per day with app installed and never opened (alarms and one daily sync) |
| APK/AAB download size | under 15 MB per ABI. Web initial payload under 2 MB gzip |
| Network | Calendar and Tasks sync use incremental tokens. Typical sync under 20 KB |
| DB | Any screen query under 10 ms for 50k rows |

Every budget gets a CI check or a manual benchmark script (section 12).

## 2. Stack decisions

- Flutter stable, Dart 3, AOT release, Impeller on.
- State: Riverpod (code-gen free, plain providers). Always use `select` and `family` so widgets rebuild only for their slice.
- Routing: go\_router with StatefulShellRoute.indexedStack. Keep only the visible tab's expensive subtree alive (see 10.4).
- DB: Drift on SQLite. Native: sqlite3 with WAL, `PRAGMA synchronous=NORMAL`, `foreign_keys=ON`, background isolate (`NativeDatabase.createInBackground`). Web: Drift WASM with OPFS, fallback IndexedDB.
- Google: plain `http` calls to the REST APIs with a thin hand-written client for the few endpoints needed (events.list, events.insert/patch/delete, calendarList, tasks, tasklists). Avoid the heavy `googleapis` package to cut size and tree-shaking issues. Sign-in via `google_sign_in` (mobile) and loopback OAuth with PKCE (desktop).
- Backend (own VPS, only for habits and focus data): Deno + Hono + PostgreSQL, JWT access (15 min) plus rotating refresh token, Argon2id password hashing, rate limiting. Never receives Google data.
- Notifications and alarms: native Kotlin module through a thin platform channel (see section 7). Do not rely on a Dart isolate waking up to ring an alarm.
- Markdown: `markdown` package parser plus a custom lightweight renderer to `TextSpan`s. Preview is lazy and cached per note version.
- Dependencies policy: every new package needs a written reason, a size check, and a maintenance check. Prefer 100 lines of own code over a transitive tree.
- Pin versions and upgrade one package at a time (past major bulk upgrades caused cascading breakage).

## 3. Architecture

Feature-first layout with clean boundaries.

```
lib/
  core/        time, ids, result types, logger, db, platform channels, theme tokens
  data/        drift tables, DAOs, remote clients, mappers, repositories
  domain/      pure Dart: entities, recurrence engine, parsers, use cases
  features/    calendar, tasks, matrix, habits, countdowns, focus, notes, tags, settings, auth, sync, alarms
  app/         shell, router, session restore, quick add
```

Rules:

- `domain/` has no Flutter or Drift imports. It is unit tested heavily.
- UI reads only from Drift streams (single source of truth for the UI). Network never feeds the UI directly.
- Writes: optimistic local write, then enqueue a row in `outbox`, then the sync engine pushes. The user never waits for the network.
- All dates stored as UTC epoch milliseconds plus an IANA zone id when the event is zone-bound. All-day items stored as a `YYYY-MM-DD` local date string, never as a timestamp (avoids the classic off-by-one-day bug).

## 4. Data model (Drift)

Common columns on syncable tables: `id` (UUIDv7 text), `createdAt`, `updatedAt`, `deletedAt` (soft delete), `dirty`, `remoteId`, `remoteEtag`.

- `events`: calendarId, title, notes (synced part), notesOverflowNoteId, location, startUtc, endUtc, startDate, endDate, isAllDay, tzId, endTzId, rrule, recurringMasterId, originalStart (for exceptions), status (confirmed/cancelled/tentative), colorId, meetUrl, reminders json, alarmPreset, visibility, transparency (busy/free).
- `event_attendees`: eventId, email, name, rsvp, isOrganizer, isSelf.
- `occurrence_cache`: eventId, startUtc, endUtc, dayKey. Rebuilt lazily for a rolling window (see 5.3). Indexed by `dayKey`.
- `calendars`: remote and device calendars, color, enabled, readOnly, source (google/device).
- `task_lists`, `tasks` (title, notes, priority, dueDate, dueTime, durationMin, rrule, repeatMode, parentId, pinned, wontDo, completedAt, sortOrder, listId, alarmPreset), `task_tags`, `smart_lists` (filter json), `subtask` via parentId with a one-level check constraint.
- `habits` (name, sectionId, frequency, weekdaysMask, weeklyTarget, intervalDays, goalType, goalAmount, unit, increment, goalDurationDays, startDate, archived, reminderTime, alarmPreset), `habit_sections`, `habit_logs` (habitId, dayKey, amount, done, skipped).
- `countdowns`, `focus_sessions`, `notes`, `folders`, `note_links`, `tags`, `tag_defaults`, `attachments` (file path, mime, size, hash).
- `alarms_index`: sourceType, sourceId, fireAtUtc, presetStep, requestCode, state. Mirror of what is registered natively.
- `outbox`: entity, entityId, op, payload, attempts, nextTryAt, lastError.
- `sync_state`: per calendar syncToken, per task list updatedMin, lastSyncAt, lastError.
- `drafts`: formType, entityId, json, updatedAt (session restore).

Indexes (MUST): events(calendarId,startUtc), events(recurringMasterId), occurrence\_cache(dayKey), tasks(listId,deletedAt,completedAt,dueDate), tasks(parentId), habit\_logs(habitId,dayKey), focus\_sessions(startUtc), notes(folderId,updatedAt), alarms\_index(fireAtUtc). Add FTS5 virtual tables for notes and tasks search.

Migrations: every schema change has a versioned Drift migration and a migration test from every previous version.

## 5. Recurrence engine (the part everyone gets wrong)

### 5.1 Scope

Pure Dart RRULE subset: FREQ DAILY/WEEKLY/MONTHLY/YEARLY, INTERVAL, BYDAY (with ordinals like 2MO, -1FR), BYMONTHDAY (including -1 for last day), BYMONTH, BYSETPOS for "last weekday", COUNT, UNTIL, WKST, plus EXDATE and RDATE. Exactly what Google Calendar emits. Property tests compare against a reference implementation in the dev tooling.

### 5.2 Correctness rules

- Expand in the event's own time zone, then convert to UTC, so DST shifts keep wall-clock time (9:00 stays 9:00).
- Monthly on the 31st: skip months without 31 (Google behavior) and offer the explicit "last day of month" option.
- Leap day yearly events: Feb 29 on non-leap years falls on Feb 28 or Mar 1 as an explicit user setting, default Feb 28.
- UNTIL for timed events is UTC with `Z`; for all-day events it is a date. Mixing them silently breaks sync.
- Week start follows the user setting (WKST) for weekly rules with INTERVAL above 1.

### 5.3 Materialization

- Query-time expansion only inside a window. `occurrence_cache` holds the visible month plus 1 month each side. Fill in a background isolate, invalidate on any edit to the master or its exceptions.
- Cap expansion at 1,000 instances per master per query. Infinite series never loop.

### 5.4 Edit scopes (MUST for events, tasks that recur)

Every edit or delete of a recurring item shows a scope sheet with three radio options and a Confirm button. Default selection: "This event".

**Delete**

1. *This event only*: create or update an exception row for that original start with `status=cancelled` (remote: PATCH instance with status cancelled, or add EXDATE for a local-only series). Series otherwise unchanged.
2. *This and following events*: set master `UNTIL` to the instant before the chosen occurrence (date form for all-day). Delete or cancel every exception at or after that date. If the chosen occurrence is the first, treat as "All events". Remote: PATCH master recurrence.
3. *All events*: soft delete master and all its exceptions (one transaction). Remote: DELETE master.

Special cases: if COUNT is set, convert to an explicit UNTIL before splitting; if only one occurrence remains, collapse to a non-recurring event; deleting the last remaining occurrence deletes the master.

**Edit**

1. *This event*: create an exception row linked by `recurringMasterId` and `originalStart` with the changed fields only.
2. *This and following*: split the series. Truncate the old master with UNTIL, create a new master from the chosen occurrence with the new values and the same rule (or the edited rule). Re-parent later exceptions to the new master when their original start still matches the new series, otherwise drop them and tell the user in a snackbar.
3. *All events*: patch the master. Exceptions keep their individual overrides unless the user changed time fields, in which case ask "Keep changes made to individual events?" (Keep / Reset).

Also handle: drag-moving one occurrence on the timeline (always scope-asked, defaulting to this event), changing the recurrence rule itself (scope fixed to this and following or all, "this event only" is hidden), changing only the title or color (ask scope), and changing the calendar of a recurring event (all events only).

**Tasks that recur**: completing the task closes the current occurrence and creates the next one. Setting: *repeat from due date* (default) or *repeat from completion date*. Deleting a recurring task offers "This task only" (skip occurrence) or "This and all future" (ends the series). Skip occurrence is also a swipe action.

### 5.5 Edge behaviors

- Undo snackbar (6 s) for every delete and move, restoring the exact previous rows and cancelling queued outbox operations.
- Exceptions that become identical to the master are pruned.
- Remote conflicts on a recurring series use the series etag; on conflict, re-fetch the series and re-apply the user's intent, not a blind overwrite.

## 6. Sync engine

### 6.1 Principles

- Offline-first. Outbox plus incremental pull. Idempotent operations. Safe to kill at any point.
- One Sync coordinator (single-flight). Triggers: app resume (if last sync older than the interval), manual button, pull-to-refresh on Calendar and Tasks, outbox non-empty after a write (debounced 5 s), periodic background (WorkManager, minimum 15 min, default 30 min, doubled in power saving, only when network is available and battery not low).
- No polling timers while the app is in the foreground. Optional Google push channels are not used (needs a public HTTPS endpoint and would touch a backend, violating CASA avoidance).

### 6.2 Google Calendar

- Initial sync: `events.list` with `timeMin` (1 month back) and `timeMax` (3 months ahead), `singleEvents=false`, `showDeleted=true`. Save `nextSyncToken` per calendar.
- Incremental sync: use the sync token. On HTTP 410 drop local synced rows of that calendar inside the window and do a full resync (keep dirty local rows).
- Window extension: when the user navigates beyond the synced range, fetch that extra range on demand and cache it, with a loading shimmer for only the missing days.
- Push outbox ops in order per entity. Use `If-Match` with the etag. Retry with exponential backoff and jitter. 4xx other than 401/403/404/409/410/429 move the op to a visible "failed changes" list with a Retry and Discard action.
- 401: silent token refresh, then prompt re-auth non-blockingly. 403 rateLimitExceeded and 429: honor `Retry-After`.
- Attendees, RSVP, conferenceData (Meet creation via `conferenceDataVersion=1`), `sendUpdates` per the "invitation emails" toggle.
- Long descriptions: first 8,000 characters synced, remainder stored in a linked local note with a footer line in the synced part ("continued in Ephemeron"). Merge on read.

### 6.3 Google Tasks

- `tasks.list` with `updatedMin`, `showDeleted`, `showCompleted`, `showHidden`. Local fields not supported by Google stay local; the sync mapper never overwrites them.
- Local is authoritative on conflicts for local-only fields, last-writer-wins by `updated` for shared fields.
- Due time is not supported by Google Tasks (date only): store the time locally and show a small "time is local" hint in the editor.

### 6.4 Sync UX

- Status chip: Synced, Syncing, Offline (with pending count), Error (tap for details).
- Grey title for unsynced changes, per the requirements, and a tiny cloud-off icon on rows with pending ops.
- Developer log capped to 500 lines, no tokens or personal data in logs.

### 6.5 Backend sync (habits, focus)

- Per-table changesets with `updatedAt` cursors, tombstones, batch upload up to 200 rows, gzip, and delta only. Server-side validation, per-user row-level security, rate limits.
- Account deletion (LGPD): one button that deletes remote data and offers export first.

## 7. Alarms and notifications (battery critical)

### 7.1 Android (priority)

- Native Kotlin: `AlarmManager.setAlarmClock` for Medium, Strong and Constant (highest reliability, exempt from Doze) and `setExactAndAllowWhileIdle` for Light. Use `USE_EXACT_ALARM` where Play policy allows it (calendar and alarm apps) with `SCHEDULE_EXACT_ALARM` runtime flow as fallback and a clear explainer screen.
- Full-screen intent for the ring screen (`USE_FULL_SCREEN_INTENT`, with the Android 14 permission check and a settings deep link), `showWhenLocked`, `turnScreenOn`. Alarm sound plays through a native `MediaPlayer` on the alarm audio stream. No Dart code needed to ring.
- **Rolling window scheduling**: never register thousands of alarms. Keep the next 48 hours plus the next N (about 60) future alarms registered. A daily WorkManager job and every app open re-extend the window from `occurrence_cache` and `alarms_index`.
- Re-register on: boot completed, app update (`MY_PACKAGE_REPLACED`), time change, timezone change, locale/date change, exact-alarm permission granted.
- Notification channels: Light, Medium, Strong, Constant, Habit, Focus. Users manage sound and vibration per channel in system settings (link from the app).
- Actions: Snooze (default 10 min, user-defined 1 to 60 min) and Mark done work from the notification via a broadcast receiver that updates the DB natively and queues a Dart-side refresh. No app launch needed.
- Ring screen: cannot be dismissed with back or swipe, must Snooze or Done (or Dismiss for events). Auto-snooze after 30 s of no interaction, volume ramp-up, vibration pattern, optional flashlight blink, one-tap "Open item".
- Constant alert: repeats every 1 minute until resolved, capped at 30 minutes, then a missed-alarm notification persists.
- Missed alarm log: if the device was off, show "You missed X" notifications on next boot.
- Do Not Disturb: alarms use the alarm category so they ring through DND by default for Strong and Constant, with a setting to respect DND for Light and Medium.
- Battery-optimization guidance screen for aggressive OEMs (Xiaomi, Samsung, Huawei, Oppo) with deep links, shown once after the first alarm is created.

### 7.2 iOS and others

- iOS: `UNUserNotificationCenter` with the 64 pending limit. Same rolling window with a cap of 60. Use time-sensitive interruption level for strong alerts and request the Critical Alerts entitlement only if approved. No full-screen ring screen is possible: say so in settings.
- Desktop: system notifications plus a lightweight in-app window alarm while the app is running or in tray. Configurable sound paths.
- Web: show the "alarms unavailable" banner, offer ICS export as a workaround.

### 7.3 Defaults for reminders

- Per-calendar and per-tag defaults for reminder offsets and presets. All-day events default to 9:00 the day before or the same morning (setting).
- Reminder offsets: at time, 5, 10, 15, 30, 60 min, 1 day, 2 days, 1 week, custom value and unit.
- Alarm test button in settings: "Ring in 10 seconds".

## 8. Feature plan by module (with UX additions)

Each module lists required items first, then **Additions** that improve the experience.

### 8.1 App shell and navigation

Required: seven sections, pinned five plus More sheet, drag reorder, floating pill or edge-to-edge bar, indexed stack, last-screen restore. **Additions**: haptics on tab change (toggleable), long-press a tab to open its quick add, double tap tab to scroll to top or jump to today, badge counts (overdue tasks, habits left today), predictive back gesture support, adaptive layout (NavigationRail on tablets, desktop sidebar with keyboard shortcuts), landscape layouts, foldable support, edge-to-edge system bars, tablet two-pane (list plus detail).

### 8.2 Session restore and drafts

Required: last screen, open form, in-progress drafts. **Additions**: drafts autosave debounced at 500 ms to the `drafts` table, never on every keystroke to disk synchronously. "Restore draft?" banner instead of silently reopening if the draft is older than 24 h. Drafts expire after 7 days. Process-death safe using `RestorationMixin` for scroll positions.

### 8.3 Quick add

Required: floating pill, five entity types, target switcher, shorthands (`#tag`, `~list`, `-p1..-p4`), context buttons, advanced options, Markdown with preview, image attach and paste, discard confirm. **Additions**:

- Natural-language date and time parsing in the title for English and Portuguese ("amanha 15h", "next friday 9am", "in 2 hours", "every monday", "todo dia 8h") with a highlighted chip and one-tap undo of the parse. Parser is local, rule-based, offline.
- Smart default type inference: a title with a time becomes an event, otherwise a task.
- Recent tags, lists and calendars as chips. Last-used calendar and list remembered.
- Voice input via the system speech recognizer (optional, no custom model).
- Android share target: share text, links, images or files from any app into quick add. Home screen shortcut and quick settings tile for "Add task".
- Keep adding: "Save and add another" button, keeps type and list.
- Duplicate detection hint for same title at same time.

### 8.4 Authentication

Required: Google sign-in (Calendar and Tasks scopes together), backend email and password (min 8), session restore, logout, desktop custom OAuth. **Additions**: use incremental scopes when possible (request Tasks only when the user turns on Tasks sync), tokens in the platform keystore (`flutter_secure_storage` with Android Keystore), biometric lock option for the app, "works without any account" mode (fully local), password reset by email, email verification, account deletion and data export, clear explanation screen "Google data never goes to our server", handle revoked access gracefully with a re-connect banner, multiple Google accounts (SHOULD, phase 9).

### 8.5 Calendar

Required: month grid, 3/4/7-day and daily timelines, table formats Month/2 weeks/week, day selection, Esc to month, full event CRUD, RSVP, recurrence, scopes, notes, overflow, linked note, device calendars, settings. **Additions**:

- **Rendering**: month grid and timelines are custom `CustomPainter` or `RenderBox` widgets with virtualization (only visible days built), event layout precomputed in an isolate (column packing for overlapping events), text painters cached. No heavy calendar package.
- Timeline: current-time line, auto-scroll to now, pinch to change hour height, drag on empty space to create, long-press to move, drag edges to resize with snapping (5, 10, 15 min), edge auto-scroll while dragging, haptic tick on snap, all-day row that collapses and expands, multi-day events spanning bars.
- Views: Agenda (infinite list grouped by day), Year heat-map, Schedule view; week numbers, optional weekends hide, 5-day work week.
- Go-to-date picker, Today button with a day number badge, swipe between ranges with lightweight transition, remember the last view type.
- Event details sheet: map link for location (open in maps), tap Meet link to join, copy link, add to other calendar, duplicate, share as text or ICS, print-friendly day export.
- Time zones: event time zone and end time zone, secondary time zone column in day view, "Show in my time zone" label when an event is in another zone.
- Conflict hint: gentle warning when a new event overlaps an existing busy event. Free/busy (transparency) toggle.
- Event types: default duration setting (30, 60 min), birthday and holiday calendars (Brazil and region national holidays bundled offline, no network), "declined events" visibility toggle, hide completed tasks on the calendar toggle.
- Tasks with due times appear on the timeline as a lighter block with a checkbox (SHOULD).
- Invitations: accept, decline, propose via Google link, "Add note to response", RSVP for recurring events with scope (this, following, all).
- Moving an event between calendars, color override per event, calendar color per calendar, event reminders list with custom values.
- Search events by title, location, attendee. Recent searches.
- Time-picker UX: a fast keyboard-friendly time input, 12 or 24 hour per locale, end-time auto-shift when start changes, end before start validation with inline message.
- Accessibility: semantic labels per cell ("Tuesday 14, 3 events"), larger-text scaling in all views, high contrast mode.
- Widgets (Android Glance or native): Agenda, Month, Next event, Tasks today, Habits today, Focus timer. Update on data change only, no periodic refresh.

### 8.6 Tasks

Required: lists, properties, smart lists, custom smart lists, operations, Google Tasks mirror. **Additions**:

- Swipe actions (complete, schedule, delete, skip occurrence) with undo; long-press multi-select with bulk move, tag, priority, date, delete.
- Inline subtask add (Enter to add the next), drag to reorder subtasks, progress ring "2/5", promote subtask to task.
- Quick date chips (Today, Tomorrow, Next Monday, Pick, None), "Snooze to later today / tomorrow / weekend".
- Overdue section with "Reschedule all to today".
- Trash: 30-day auto purge, restore, empty trash, permanent delete confirmation. Won't Do separate from Completed.
- Duplicate task, move to list, share as text, convert task to event or note.
- Smart list builder with AND/OR across tag, priority, date range, list, has due time, recurring, plus saved sort and "show completed" toggle; counts per list computed with indexed SQL.
- Subtle completion animation (respects Reduce animations). Completed section collapsible, "Hide completed after X days".
- Repeat modes (see 5.4), checklist-style "repeat days after completion".
- Export list as Markdown or CSV.

### 8.7 Eisenhower Matrix

Required: four quadrants and tap to edit, sorting menu. **Additions**: classification rule is explicit and visible (Important = priority high or medium, Urgent = due within 2 days or overdue; thresholds configurable), drag a task between quadrants to change priority or due date with undo, filter by list or tag, collapse quadrants, tap a quadrant header for a full-screen list, counts per quadrant, empty-state tips, an Unclassified tray for tasks with no priority and no date.

### 8.8 Habits

Required: all frequency modes, goal types, sections, duration, archive, reminders, logging, date navigator, streaks, focus credit. **Additions**: one-tap complete with long-press for amount entry, 7-day swipe strip above the list, skip day (does not break the streak), vacation mode (pause all), streak rules clear per frequency (weekly target streaks count weeks), current and best streak, monthly heat-map per habit, weekly and monthly completion rate, backfill missed days, edit past logs, habit detail screen with notes, reorder inside sections, custom sections with icons, templates (drink water, read, exercise, meditate), completion celebration at the end of the goal duration with "extend or archive", smart reminder that skips if already done today (checked at fire time natively), widget with one-tap logging, optional negative habits ("avoid X").

### 8.9 Countdowns

Required: types, templates, yearly recurrence, show age, past display, alerts 3 days before and on the day. **Additions**: sort by next date or manually, grouped sections (Upcoming, Passed), custom alert offsets, notification at a chosen time of day (default 9:00), detail view with weeks, days and hours breakdown, "time since" tracking for quit-streak use cases, pin one countdown to a home widget, share image card, add to calendar as all-day event, optional one-time birthday import from contacts, leap day handling, auto-archive passed ones after N days.

### 8.10 Focus

Required: Pomodoro 25/5, stopwatch, link to task or habit, keep screen on, totals, monthly screen, session recording. **Additions**:

- **Timer correctness and battery**: store `startedAt` and `targetEndAt` timestamps, compute elapsed on each frame while visible, and register one native alarm for the end. No periodic background ticking. Survives app kill, reboot, and sleep.
- Ongoing notification with a system chronometer (rendered by the OS, no per-second updates from the app).
- Configurable durations, long break after 4 cycles, auto-start next phase option, end-of-phase sound and vibration, session note on finish, "mark task complete" prompt on finish.
- Abandoned session recovery (app killed): "Keep X minutes?".
- Stats: daily bars, weekly, monthly calendar, by task, by habit, by tag, streak of focus days, best time of day, CSV export.
- Auto credit to time-based habits (minutes and hours), with undo.
- Optional Do Not Disturb toggle during focus (needs permission), minimal OLED black screen mode.

### 8.11 Notes

Required: CRUD, Markdown preview/edit, images, smart list formatting, date grouping, nested folders, breadcrumbs, counts, drag into folders, delete folder to parent, search, event-linked notes. **Additions**: autosave (debounced 800 ms) with no Save button, undo and redo, Markdown toolbar (bold, italic, list, checklist, heading, link, code, quote), tappable checklist items in preview, pin notes, move via sheet (not only drag), duplicate, note templates (meeting notes with attendees and date), backlinks `[[Note title]]` (SHOULD), word and character count, copy and share as Markdown, export folder to a ZIP of .md files, import .md and .txt, image compression (max 1600 px, WebP quality 80) in a content-addressed attachments folder with orphan cleanup, fullscreen image viewer with zoom, trash with restore, FTS5 search with highlighted snippets, sort options, link detection, optional biometric note lock (SHOULD), large-note performance via lazy preview chunking.

### 8.12 Tags

Required: name, color, defaults, autocomplete, many-to-many, filter. **Additions**: tag management screen (rename, recolor, merge, delete with confirmation and usage count), autocomplete ranked by recency and frequency, hierarchical tags `#work/project` (SHOULD), tag counts, tap a tag chip anywhere to filter, case-insensitive duplicate prevention.

### 8.13 Settings and appearance

Required: all listed items. **Additions**: language (English and Portuguese bundled, system default), date and time formats, default calendar, default reminder, default event duration, theme light, dark, AMOLED black and automatic, optional dynamic color (Material You), font scale preview, live preview of color choices, settings search, "Reset to defaults", full backup and restore (JSON plus attachments ZIP) with scheduled automatic local backups to a user-picked folder, ICS import and export, data usage screen (storage by type, cache clearing), "Test alarm" and "Test notification", sanitized diagnostics export, about screen with licenses, "What's new", privacy policy link, delete all data.

## 9. Cross-cutting UX checklist (commonly forgotten)

- Undo for every destructive action. Confirmations only for irreversible or scope-dependent ones.
- Every list has a loading skeleton, an empty state with a useful action, and an error state with Retry.
- First-run onboarding in 3 screens max: permissions explained one at a time at the moment of need (notifications, exact alarms, calendar read), skip always allowed.
- Permission denial paths: the feature degrades and shows a one-tap link to system settings.
- Offline indicator that is calm, not alarming. All local features work offline.
- Global search (events, tasks, notes, habits, countdowns, tags) from a single field with type filters.
- Keyboard (desktop and web): N new, T today, / search, arrows navigate, Esc back, Ctrl+Z undo, 1 to 7 switch views, Enter saves forms, Ctrl+Enter in notes, full focus traversal.
- Accessibility: TalkBack and VoiceOver labels, 48 dp touch targets, AA contrast, text scale up to 200%, reduce motion honored, color is never the only signal (icons and patterns for priority).
- Localization-ready strings from day one (ARB files), plural rules, RTL-safe layouts.
- Time handling: respects system 12/24 hour, DST transitions tested, device time zone change handled live.
- Error messages in plain language with what to do next.
- Haptics subtle and optional. Animations 150 to 250 ms, disabled when Reduce animations or power saving.
- App shortcuts (long-press icon): New task, New event, Start focus. Per-app language support on Android 13+.
- Data portability: ICS, CSV, Markdown, JSON export, all offline.

## 10. Performance and battery engineering

### 10.1 Startup

- Show the native splash, then render the shell immediately with cached last-state from a tiny local file. Open the DB and warm providers after the first frame. Lazy-load every feature provider.
- Defer notification plugin init, Google client init, backend client. Subset Fraunces and Inter to needed glyphs and two or three weights each.
- No large synchronous JSON or Markdown work before the first frame.

### 10.2 Rendering

- `const` widgets everywhere, `ListView.builder` with `itemExtent` or `prototypeItem` when fixed, `RepaintBoundary` around heavy cells, no `Opacity` or `ShaderMask` in scrolling content, avoid `saveLayer`, image `cacheWidth` and `cacheHeight`.
- Glassmorphism off by default; blur only on the nav bar, never on scrolling content; auto-off in power saving.
- Record frame timings in an integration test on a low-end device.

### 10.3 Data

- All queries via indexed Drift DAOs, streams with `distinct`, large result mapping in an isolate. Page lists (50 at a time). Batch inserts in transactions. `VACUUM` rarely (idle and charging). WAL checkpoint after sync.
- Compute derived values in SQL (counts, streaks) or cache them in small summary tables updated on write paths.

### 10.4 Memory

- Dispose controllers, cap the image cache (about 50 MB), cap provider keep-alive, keep only the active tab's heavy views (timeline painters) alive. Release occurrence caches when the app goes to background.

### 10.5 Battery

- No foreground polling, no wakelocks except Focus keep-screen-on (user chosen), no Dart-side wake-ups for alarms, one batched network sync, coalesced writes, WorkManager constraints (network connected, battery not low).
- Power saving mode (Auto, On, Off): doubles sync intervals, disables animations and blur, defers non-urgent sync.
- No location, Bluetooth, or sensor usage at all.
- Battery benchmark: 24 h run with `dumpsys batterystats` or Battery Historian, compared against a no-app baseline.

### 10.6 Size

- `flutter build apk --split-per-abi --obfuscate --split-debug-info --tree-shake-icons`, R8 and resource shrinking, unused locales and fonts removed, WebP images, `--analyze-size` on every release. Web: measure CanvasKit versus skwasm, defer rarely used screens (settings, focus stats, export).

## 11. Security and privacy (LGPD, CASA-avoidant)

- Google tokens only on device in the keystore. The backend never sees Google tokens, events, or tasks.
- Backend minimal data: email, password hash, habits, focus sessions. Data minimization, purpose limitation, explicit consent, privacy policy in Portuguese and English, DPO contact, export and deletion endpoints, retention rules, breach procedure.
- TLS 1.2+ only, default certificate checks, no analytics SDKs, crash reporting opt-in and scrubbed.
- Android: sensitive files excluded from backup or encrypted, optional `FLAG_SECURE` for private notes, no cleartext traffic, minimal exported components, intent validation for share targets.
- Server: parameterized queries, input validation, per-user authorization on every route, rate limits, refresh token rotation with reuse detection, Argon2id, secrets via environment, audit logs without personal content.
- Dependency hygiene: lockfile, `dart pub outdated` review, CI scan.

## 12. Testing and quality gates

- Unit: recurrence engine (property tests across DST, leap years, month ends), scope operations, parsers, alarm window scheduler, sync mappers, streak calculators.
- Drift migration tests for every version, repository tests with an in-memory DB.
- Sync tests with a fake Google server (recorded fixtures): 410 resets, etag conflicts, 429 backoff, offline queues, partial failure, kill mid-sync.
- Widget and golden tests for core screens in light, dark, and large text.
- Integration tests on emulator and a real low-end phone: startup time, scroll jank, memory, alarm after reboot, DST change, time zone change, Doze.
- Manual alarm matrix on Pixel, Samsung, Xiaomi.
- CI: format, strict analyze, tests, size report, benchmark thresholds (fail on regression above 10%).

## 13. Risks and pitfalls

- Recurring scope splits are the top bug source: build and test them before the UI.
- OEM battery killers can block alarms: the native approach and the guidance screen mitigate this.
- Google API quotas: incremental tokens and batching keep calls low. Never poll.
- Web limits: no alarms; Drift WASM needs COOP and COEP headers for OPFS.
- Dependency drift: pin versions, upgrade individually.
- Time zone and all-day mistakes: date strings for all-day, UTC plus zone for timed.
- Scope creep: respect the phase gates below.

## 14. Build phases

1. **Foundation**: repo, CI, theme tokens, shell and navigation, Drift schema and migrations, logger, settings storage. *Accept*: app starts within budget, tabs switch smoothly.
2. **Recurrence and time core**: domain engine, tests, occurrence cache. *Accept*: property tests green.
3. **Tasks, lists, tags, smart lists, trash, quick add shorthands, matrix**. *Accept*: full local task flow offline with undo.
4. **Calendar local**: views, timeline rendering, event CRUD, scopes, device calendars. *Accept*: 60 fps month and timeline on a low-end device.
5. **Alarms**: native Android module, rolling window, ring screen, snooze, reboot recovery. *Accept*: alarm matrix passes.
6. **Google sync**: auth, Calendar incremental sync, Tasks mirror, outbox, error handling. *Accept*: fake-server suite green, 3-day real account soak test.
7. **Notes**: folders, Markdown, attachments, FTS search, event links, overflow.
8. **Habits, countdowns, focus**: local first, then backend account and sync. *Accept*: timers survive app kill, streaks correct.
9. **Polish**: widgets, shortcuts, share target, backup and export, onboarding, localization, accessibility, desktop, iOS and web parity, multiple Google accounts.
10. **Release hardening**: 24 h battery benchmark, size audit, security review, store assets, privacy policy, staged rollout.

## 15. Handoff notes for the implementing model

- Work one phase and one change per prompt, commit after each, run tests before moving on.
- Never invent APIs: check official docs for Google Calendar, Google Tasks, Android AlarmManager, and Drift before use.
- If a decision is not covered here, choose the lighter-weight option and record it in `docs/decisions.md`.

**Recommended model and effort for the build**: Claude Sonnet 5.5 at Medium effort for routine feature work; High effort with thinking on for the recurrence engine, sync engine, native alarm module, and Drift migrations; Low effort for UI boilerplate, strings, and tests that mirror existing ones. Higher effort adds deeper edge-case reasoning (DST, conflicts, lifecycle) at more token cost.
