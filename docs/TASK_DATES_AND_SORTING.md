# Task Dates and Sorting

## Task date model

Tasks keep two independent optional dates, both stored as local `YYYY-MM-DD`
strings:

- `dueDate` is the deadline. `dueTime` (minutes of day) still belongs to the
  due date and controls the timed calendar block and reminders.
- `plannedDate` is when the user intends to work on the task. It has no time
  component and is nullable.

A task may have either date, both, or neither. Clearing a date writes `null`;
updating a task uses a nullable callback so the cleared value reaches Drift.
`plannedDate` is local-only: it is not sent to Google Tasks, which has no
equivalent field. Google-imported tasks leave `plannedDate` null and fall back
to their due date. Backups include `plannedDate`, so restore does not lose it.

Recurring task completion creates the next task. When both dates exist, the
planned date moves by the same day delta as the due date. For example, a daily
task due 2026-03-02 planned 2026-03-01 becomes due 2026-03-03 and planned
2026-03-02.

## Calendar behavior

Task occurrences use the planned date when set, otherwise the due date:

- A planned-date task is an all-day occurrence on `plannedDate`, even if a
  `dueTime` exists. The calendar does not show it on its due date.
- A due-only task keeps the existing behavior: all-day when `dueTime` is null,
  otherwise a timed block using `dueTime` and `durationMin` (default 30 min).

The occurrence rebuild loads tasks whose effective date falls inside the
window. The window cache remains derived data and is rebuilt normally.

## Sort modes

Sorting is a presentation concern stored in SharedPreferences, not a new
database table.

Tasks:

- `custom` - local `sortOrder` order.
- `name` - case-insensitive title.
- `created` - newest first.
- `due` - due date ascending, undated tasks last. This is the default and
  preserves the previous behavior.

Task lists:

- `custom` - local `sortOrder` order. This is the default.
- `name` - case-insensitive name.
- `created` - newest first.

Comparators live in `features/tasks/application/task_sorting.dart`. Pinned
tasks stay on top in every mode except explicit custom order. Ties fall back to
`sortOrder` and then id so ordering stays deterministic. Normal list chips on
the Tasks screen follow the active list sort. Smart lists keep the sort
saved inside their filter JSON; selecting one does not apply the global task
sort.

## Drag UX

Custom task order uses a single reorderable task list, with no overdue/rest
split. Long-press an item to drag it; swipe-to-complete/delete and tap-to-edit
remain available on the same row. The list updates optimistically and persists
`sortOrder` values `0..n` in one transaction.

The list manager uses the same long-press pattern in custom mode. Changing to
Name or Created hides dragging and sorts the visible lists without rewriting
stored positions, so returning to Custom order restores the user's arrangement.

Reorder operations are local-only. Google Tasks has no position field, so they
do not write updated timestamps or enqueue outbox operations.

## Schema migration and compatibility

Migration v9 to v10 adds one nullable column:

```sql
ALTER TABLE tasks ADD COLUMN planned_date TEXT;
```

`schemaVersion` is now 10. Existing rows keep a null planned date and continue
to behave as due-only tasks. No data rewrite is required. Backups from before
the feature restore with a null planned date; new backups carry the field.

Sort settings add two SharedPreferences keys, `tasks.sort` and `lists.sort`.
Missing or unknown stored values fall back to `due` and `custom`, matching the
old behavior.

## Verification

Run from `app/`:

- `dart format <changed files>`
- `flutter analyze`
- `flutter test`

Covered tests:

- task repository: planned date create/update/clear, recurring planned-date
  shift, reorder sortOrder and outbox neutrality, task/list comparators.
- occurrence cache: planned date wins over due date and is all-day; due-only
  timed fallback is unchanged.
- backup: export/import round-trip preserves plannedDate.
- settings: taskSort/taskListSort defaults and round-trip.
- db: schema version 10 and nullable `planned_date` column.

Drag gestures are code-reviewed rather than covered by a dedicated widget test;
the repository reorder path and comparators are covered.

Verified on 2026-11-04: `flutter analyze` reported no issues and the full
`flutter test` suite passed (261 tests).
