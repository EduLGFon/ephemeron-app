# Test performance

Date: 2026-11-02. Machine: 4-core Linux, 15 GB RAM, Flutter 3.47.8.
Baseline: `flutter test` from `app/` with 33 test files and 132 tests.

## Result

| Metric | Before | After |
|---|---|---|
| Wall time | 94.5 s | 27.0 s |
| Suite compile/load | 116.8 s (sum, partly overlapped) | 14.3 s (one kernel) |
| Test execution | 58.6 s (sum, partly overlapped) | 9.4 s |
| Test files compiled | 33 | 1 |
| Tests run | 132 | 133 (132 + runner guard) |

Speedup is 3.5x on an otherwise idle machine. The same suite took 43.8 s and
then 69.0 s while other Flutter builds and test runs shared the same 4 cores;
test execution stayed around 9 s to 15 s and the extra time was compile
contention. The structural result is one kernel instead of 33. The single
compile is now the largest remaining fixed cost.

Work continued in parallel while this change was being verified. The new
`session_restore` and `calendar_color` cases were added to `test/cases/`, the
runner guard caught the stale aggregate, and the final tree has 35 case files,
140 tests, plus the guard. That run passed in 41.3 s with load average 5.0.
The 27.0 s figure above is the same original 132-test suite on an idle machine.

## Why it was slow

Flutter emits a complete kernel for every test file and sends those compile
requests through one serial queue. Each suite therefore pays a fixed cost that
is mostly independent of its tests. In the baseline, 33 files paid that cost,
and the compile/load sum (116.8 s) was larger than total wall time because some
testing overlapped with compilation. Individual tests were fast: 132 tests
summed to 58.6 s, and most of that was the first `testWidgets` in each file
paying binding and font setup again.

This is an upstream `flutter test` design limit, not a defect in the app tests:
[flutter/flutter#168268](https://github.com/flutter/flutter/issues/168268).
The upstream investigation also shows that merging entrypoints removes the
cost linearly. `dart_test.yaml` `filename` did not restrict discovery in this
Flutter version, so the case files were renamed rather than filtered.

## Baseline compile/load ranking

| # | Test file | Compile/load (s) |
|---|---|---|
| 1 | `widget_test.dart` | 17.09 |
| 2 | `recurrence_test.dart` | 17.06 |
| 3 | `backend_auth_test.dart` | 5.43 |
| 4 | `event_scope_test.dart` | 3.47 |
| 5 | `alarm_repository_test.dart` | 3.47 |
| 6 | `habits_screen_test.dart` | 3.33 |
| 7 | `db_test.dart` | 3.26 |
| 8 | `countdowns_screen_test.dart` | 3.11 |
| 9 | `home_widget_binder_test.dart` | 3.08 |
| 10 | `widget_image_test.dart` | 3.01 |
| 11 | `l10n_test.dart` | 2.94 |
| 12 | `quick_add_test.dart` | 2.86 |
| 13 | `timeline_view_test.dart` | 2.82 |
| 14 | `timeline_layout_test.dart` | 2.74 |
| 15 | `alarm_window_test.dart` | 2.72 |
| 16 | `task_repository_test.dart` | 2.63 |
| 17 | `widget_config_test.dart` | 2.48 |
| 18 | `backup_test.dart` | 2.47 |
| 19 | `home_widget_test.dart` | 2.45 |
| 20 | `parser_test.dart` | 2.41 |
| 21 | `home_widget_callback_test.dart` | 2.40 |
| 22 | `focus_screen_test.dart` | 2.39 |
| 23 | `backend_sync_test.dart` | 2.35 |
| 24 | `headless_widget_push_test.dart` | 2.31 |
| 25 | `sync_engine_test.dart` | 2.28 |
| 26 | `search_test.dart` | 2.21 |
| 27 | `settings_test.dart` | 2.20 |
| 28 | `habit_focus_test.dart` | 2.19 |
| 29 | `occurrence_cache_test.dart` | 2.18 |
| 30 | `onboarding_test.dart` | 2.10 |
| 31 | `note_repository_test.dart` | 2.00 |
| 32 | `auth_screen_test.dart` | 1.82 |
| 33 | `habit_streak_test.dart` | 1.59 |

The first two suites include the cold compiler start. The remaining suites pay
roughly 1.6 s to 5.4 s each for their own kernel.

## Baseline slowest tests

| # | Test | File | Duration (s) |
|---|---|---|---|
| 1 | app builds | `widget_test.dart` | 7.22 |
| 2 | running session finishes from the screen | `focus_screen_test.dart` | 5.08 |
| 3 | habit complete writes today log | `habits_screen_test.dart` | 4.98 |
| 4 | day view shows hours, header and event | `timeline_view_test.dart` | 4.92 |
| 5 | countdown appears in upcoming | `countdowns_screen_test.dart` | 4.43 |
| 6 | search screen localizes titles | `l10n_test.dart` | 4.35 |
| 7 | binder refreshAll does not throw | `home_widget_binder_test.dart` | 3.39 |
| 8 | backend sign-in shows sync controls | `auth_screen_test.dart` | 2.46 |
| 9 | heatmap lays out with unbounded height | `widget_image_test.dart` | 1.57 |
| 10 | delete single creates cancelled exception | `event_scope_test.dart` | 1.23 |
| 11 | multi-day view shows all days and scrolls | `timeline_view_test.dart` | 1.19 |
| 12 | export/import round-trip preserves rows | `backup_test.dart` | 1.14 |
| 13 | create list and task, complete recurring creates next | `task_repository_test.dart` | 0.94 |
| 14 | headless push does not throw on empty db | `headless_widget_push_test.dart` | 0.87 |
| 15 | keyboard Ctrl+= and Ctrl+- zoom the timeline | `timeline_view_test.dart` | 0.85 |
| 16 | rebuild expands a daily master into the window only | `occurrence_cache_test.dart` | 0.77 |
| 17 | search finds rows across entities | `search_test.dart` | 0.76 |
| 18 | pull saves token, second pull sends it | `sync_engine_test.dart` | 0.76 |
| 19 | nested folders, move, delete reparents to parent | `note_repository_test.dart` | 0.74 |
| 20 | rebuild tolerates non-IANA tz abbreviations | `timeline_view_test.dart` | 0.71 |
| 21 | month grid image builds | `widget_config_test.dart` | 0.66 |
| 22 | habit log, skip, backfill and streaks | `habit_focus_test.dart` | 0.65 |
| 23 | in-memory db creates schema and inserts calendar | `db_test.dart` | 0.63 |
| 24 | task custom offsets schedule one reminder each | `alarm_repository_test.dart` | 0.61 |
| 25 | pinch zooms the timeline | `timeline_view_test.dart` | 0.52 |

The large widget-test durations were mostly per-file setup, not test logic.
Running them in one process removed the repeated binding, font, and first-frame
cost. After aggregation, only `auth_screen` and `widget app builds` are above
one second:

| Test | Before (s) | After (s) |
|---|---|---|
| backend sign-in shows sync controls | 2.46 | 2.53 |
| app builds | 7.22 | 0.84 |
| habit complete writes today log | 4.98 | 0.54 |
| search screen localizes titles | 4.35 | 0.47 |
| day view shows hours, header and event | 4.92 | 0.34 |
| running session finishes from the screen | 5.08 | 0.32 |
| binder refreshAll does not throw | 3.39 | 0.22 |
| countdown appears in upcoming | 4.43 | 0.22 |

`auth_screen` is the first `testWidgets` in the combined process, so it pays
the one-time binding and font setup. The before/after numbers for that test are
effectively the same; it is the only widget test that did not benefit from
aggregation, and moving it earlier would just move the cost to another test.

## Duplicate and low-value test audit

Exact duplicates: none. All 132 test names are unique.

Semantic overlaps that were checked and kept:

| Area | Overlap | Decision |
|---|---|---|
| Home widget images | `widget_config` builds the month grid and week bars; `widget_image` checks the same widgets under unbounded height | Keep. One checks rendered text/type, the other checks a layout invariant that used to crash. |
| Parsing | `parser` tests direct parser output; `quick_add` tests the quick-add shorthand layer, which also emits an RRULE | Keep. Different public entry points and different assertions. |
| Settings | `settings`, `onboarding`, and `l10n` all use `SettingsRepository` with mock preferences | Keep. Each covers a different persisted field. |
| Schema | `db` verifies schema version, FTS table, and cache index; every repository test creates the schema | Keep. The direct schema pins catch migration mistakes before repository behavior masks them. |
| Recurrence | `recurrence` tests RRULE expansion; `event_scope` tests edit/delete scopes; `occurrence_cache` tests the cache rebuild | Keep. Three separate layers, all with distinct failure modes. |
| Sync | `sync_engine` covers Google sync; `backend_sync` covers habit/focus changesets | Keep. Different engines and trust boundaries. |
| Auth | `backend_auth` tests session logic and HTTP contract; `auth_screen` tests the UI | Keep. Unit and widget layers. |
| App shell | `widget` smoke-builds the full app; screen tests cover individual screens | Keep. Only the full-app test catches router and provider-wiring regressions. |

No test was removed. Removing any of the above would trade real regression
coverage for a few milliseconds, while the actual cost was the per-file
compile. The only low-value edge is the `db` insert-calendar test, which is
redundant with repository setup, but it is also the cheapest direct schema
smoke test and runs in 0.63 s.

## Changes

- Moved every `test/*_test.dart` to `test/cases/*_case.dart`.
  `test/all_test.dart` is now the only file matching the default
  `*_test.dart` discovery pattern, so plain `flutter test` runs one suite.
- Added `tools/gen_test_runner.dart`, which generates the aggregate entrypoint
  with one `group` per case file. It also emits a guard test that fails if a
  case file is missing from the runner or if an old `*_test.dart` file remains.
- Updated the two relative imports between case files.
- Updated `db_case.dart` schema pin from 7 to 8 for the in-progress
  `pending_operations` migration.
- Fixed `quick_add_sheet.dart` to use Riverpod 3's `AsyncValue.value` instead
  of the removed `valueOrNull` so the suite compiles.
- Updated `AGENTS.md` with the new test layout and regeneration command.

## How to run

```bash
cd app
flutter test
```

Targeted file:

```bash
flutter test test/cases/timeline_view_case.dart
```

Targeted test name inside the aggregate (still compiles the whole suite):

```bash
flutter test test/all_test.dart --plain-name "keyboard Ctrl"
```

After adding or renaming a case:

```bash
dart run tools/gen_test_runner.dart
```

Optional local flags (not used by CI, no test assets or widget inspector are
needed):

```bash
flutter test --no-pub --no-test-assets --no-track-widget-creation
```

`--no-test-assets` is safe for the current suite: no test loads a bundled
asset. Do not add `--no-pub` to CI; CI runs `flutter pub get` explicitly and
plain `flutter test` is already correct there.

## Constraints

- Wall time is sensitive to other Flutter builds on the same machine: the
  single compile is serial and CPU-bound. On an idle 4-core machine the suite
  is about 27 s; with concurrent Flutter runs it measured 44 s to 69 s.
- Tests run in one process, so cross-file global state is now visible. The
  suite passed in this order, but new widget tests should not depend on
  process isolation for view size, locale, method-channel mocks, or
  `SharedPreferences` contents.
- A failure in one case does not stop the rest of the suite unless
  `--fail-fast` is used. Failures are grouped by case name in the reporter.
- `flutter test` output now reports `test/all_test.dart` as the suite path.
  Use `--plain-name` or the `test/cases/...` path when locating a failure.
- Coverage was not measured in this change. The aggregate loads every case
  file, so coverage collection is not cheaper than before, only compilation
  is.
