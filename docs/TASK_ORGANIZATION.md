# Task Organization: Lists and Smart Lists

## Problem

Task lists existed in the schema but were only partially usable: lists could be
created and filtered, but not renamed, recolored or deleted from the UI. The
delete path silently detached tasks and deleted the local row immediately, which
could lose the remote id before the Google Tasks delete was pushed. Smart lists
stored a filter JSON blob, but the UI only wrote `showCompleted`; there was no
builder, no saved-view management, no result count and no reactive result
stream.

This design closes those gaps without changing the Drift schema.

## Task-list management UX

- The Tasks screen shows normal list chips first, each with a color dot and a
  tooltip carrying the account/source label (`sourceLabel`: list name plus
  account e-mail, or `On this device`). Long-pressing a list chip opens the list
  manager.
- The Tasks AppBar overflow menu exposes **Manage lists** and **Manage smart
  lists**.
- **Manage lists** shows every active list with its color dot, name, source
  label and active-task count. Each row menu offers rename, change color and
  delete. Tapping a row opens the same name/color editor.
- **Create list** asks for a name and one color from the shared preset palette.
  Creation stays local-first and queues a `task_list` `create` outbox row.
- **Rename/change color** updates the local row immediately, marks it dirty and
  queues `task_list` `update`. Color is local-only: Google Tasks lists expose no
  color field, so changing color never issues a remote patch.
- **Delete list** always states the consequence and picks a safe default:
  - When another list exists, the default is **Move tasks** to a selected list.
  - With no other list, the only option is **Delete tasks**.
  - Moving keeps tasks alive in the destination list. Tasks that had no
    destination (the repository's null-list path) go to the unlisted bucket.
  - Deleting tasks soft-deletes them; they stay in Trash until the user
    restores or permanently deletes them. There is no automatic expiry.
  - The list itself is only soft-deleted (`deletedAt`) and a `task_list`
    `delete` outbox row is queued. The row and its `remoteId` survive until the
    sync engine has deleted the remote list.

## Google Tasks list sync

- `GoogleApiClient` gained:
  - `taskListCreate(title)` -> `POST /users/@me/lists`
  - `taskListPatch(listId, title)` -> `PATCH /users/@me/lists/{id}`
  - `taskListDelete(listId)` -> `DELETE /users/@me/lists/{id}`
- Outbox application for `task_list`:
  - No `remoteId`: create remotely, store the returned id/etag and clear dirty.
  - Existing `remoteId`: patch the title remotely, update the etag and clear
    dirty.
  - Delete operation or `deletedAt` set: delete the remote list when linked,
    detach any remaining local tasks from the list (foreign-key safety), then
    hard-delete the local list row. Local-only lists skip the remote call.
- Account scoping:
  - `task_list` rows are stamped with `googleAccount` after a successful push.
  - Ops owned by another signed-in account are skipped, not deleted.
- Discovery:
  - Soft-deleted local lists are never resurrected or renamed by discovery.
  - A remote list already linked to a local row is never inserted twice.
  - A 404 on a queued list delete clears the local tombstone instead of leaving
    it pending forever.
- Ordering note: list task moves/deletes are queued before the list delete. The
  list delete removes the remote catalog entry after those local task changes
  have been prepared.

## Smart lists

Saved views use the existing `smart_lists.filterJson` column. The builder
supports:

- Name and include-completed.
- Due window: any date, today, overdue, next 7 days (today plus six days), this
  month, or a custom inclusive `dueFrom`/`dueTo` range.
- Priority multi-select (P1 to P4), list multi-select and tag multi-select.
- Text query over title and notes (LIKE wildcards are stripped).
- Sort: due date, priority, newest created, or title.
- Save creates a smart list; opening an existing saved view updates it.

The Tasks screen renders smart-list chips after normal list chips, with a filter
icon and the live result count. Selecting a smart list:

- sets `selectedSmartListProvider`;
- clears the normal list filter (and the persisted selected list);
- displays the smart list's streamed result query.

Selecting **All** or a normal list clears the smart-list selection. Long-pressing
a smart chip opens edit/delete actions. The smart-list manager shows every saved
view with a live count, edit and delete. An empty result shows "No tasks match"
with an **Edit smart list** action.

Filter JSON parsing lives in `domain/tasks/smart_filter.dart` and is defensive:
invalid JSON, non-object payloads, unknown keys and wrong value types fall back
to defaults instead of throwing. Legacy filters that stored only `dueFrom` and
`dueTo` are treated as custom due windows.

## Compatibility

- No schema or migration change. `task_lists` and `smart_lists` keep their
  existing columns (`deletedAt`, `dirty`, `remoteId`, `remoteEtag`,
  `googleAccount`, `filterJson`).
- Existing list IDs, smart-list IDs, filter keys and the selected-list setting
  remain valid.
- Google list color is device-local and is preserved across sync because
  discovery updates only the name for clean rows.
- Old smart lists that stored only `showCompleted` continue to work with the new
  parser and default sort.
- Deleting a remote-backed list is backward compatible: the local row is
  retained until the remote delete succeeds, so retries and account scoping keep
  working.

## Verification

Run from `app/`:

- `dart format <changed files>`
- `flutter analyze`
- `dart run tools/gen_test_runner.dart` after adding or moving a case
- `flutter test`

Covered tests:

- `task_repository_case`: list update/delete, watchLists hides deleted, move
  tasks versus delete tasks, unlisted move, smart-list CRUD and reactive watch,
  list/tag/priority/due/query/completed filters and all four sorts, due-window
  presets.
- `sync_engine_case`: list create stores the remote id and clears dirty, rename
  patches remotely, delete removes the remote list then purges local state,
  local-only delete, account scoping and discovery tombstone/duplicate guards.
- `smart_filter_case`: invalid JSON, unknown keys, wrong types, legacy bounds,
  due presets and round-trip serialization.

Widget-level long-press behavior is code-reviewed rather than covered by a new
widget test; the existing widget smoke test still builds the app.

Verified on 2026-11-04: `flutter analyze` reported no issues and the full
`flutter test` suite passed (241 tests).
