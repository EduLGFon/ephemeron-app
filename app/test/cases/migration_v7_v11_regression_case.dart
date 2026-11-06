import 'dart:io';

import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart';

// Regression: upgrades crossing v7 and v11 in one pass must not fail with
// "duplicate column name: source_type". v7 recreates occurrence_cache with the
// current schema; v11 also recreates it, so v11 must not addColumn source_type.
// Also verifies current migrations add task occurrence state table/index.
void main() {
  test('migration from v6 to current succeeds across v7/v11', () async {
    final dir = Directory.systemTemp.createTempSync('ephemeron_v6mig_');
    final path = '${dir.path}/v6.db';
    addTearDown(() async {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    // Minimal v6 schema with tables/columns touched by migrations v7-v12.
    final db = sqlite3.open(path);
    try {
      db.execute('''
CREATE TABLE calendars (
  id TEXT NOT NULL PRIMARY KEY,
  remote_id TEXT,
  name TEXT NOT NULL,
  color TEXT,
  enabled INTEGER NOT NULL DEFAULT 1,
  read_only INTEGER NOT NULL DEFAULT 0,
  source TEXT NOT NULL DEFAULT 'device',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  dirty INTEGER NOT NULL DEFAULT 0,
  remote_etag TEXT,
  google_account TEXT
);
''');
      db.execute('''
CREATE TABLE task_lists (
  id TEXT NOT NULL PRIMARY KEY,
  remote_id TEXT,
  name TEXT NOT NULL,
  color TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  dirty INTEGER NOT NULL DEFAULT 0,
  remote_etag TEXT,
  google_account TEXT
);
''');
      db.execute('''
CREATE TABLE events (
  id TEXT NOT NULL PRIMARY KEY,
  calendar_id TEXT NOT NULL,
  title TEXT NOT NULL DEFAULT '',
  notes TEXT,
  notes_overflow_note_id TEXT,
  location TEXT,
  start_utc INTEGER,
  end_utc INTEGER,
  start_date TEXT,
  end_date TEXT,
  is_all_day INTEGER NOT NULL DEFAULT 0,
  tz_id TEXT,
  end_tz_id TEXT,
  rrule TEXT,
  recurring_master_id TEXT,
  original_start INTEGER,
  status TEXT NOT NULL DEFAULT 'confirmed',
  color_id TEXT,
  meet_url TEXT,
  create_meet INTEGER NOT NULL DEFAULT 0,
  reminders TEXT,
  alarm_preset TEXT,
  visibility TEXT,
  transparency TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  dirty INTEGER NOT NULL DEFAULT 0,
  remote_id TEXT,
  remote_etag TEXT
);
''');
      // v6 tasks: has reminders (v6), no plannedDate (v10), no v11 cols,
      // no google_account (v9), no microsoft_account (v12).
      db.execute('''
CREATE TABLE tasks (
  id TEXT NOT NULL PRIMARY KEY,
  list_id TEXT,
  title TEXT NOT NULL DEFAULT '',
  notes TEXT,
  priority INTEGER NOT NULL DEFAULT 0,
  due_date TEXT,
  due_time INTEGER,
  duration_min INTEGER,
  rrule TEXT,
  repeat_mode TEXT,
  parent_id TEXT,
  pinned INTEGER NOT NULL DEFAULT 0,
  wont_do INTEGER NOT NULL DEFAULT 0,
  completed_at INTEGER,
  sort_order INTEGER NOT NULL DEFAULT 0,
  alarm_preset TEXT,
  reminders TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  dirty INTEGER NOT NULL DEFAULT 0,
  remote_id TEXT,
  remote_etag TEXT
);
''');
      // Pre-v7 occurrence_cache (no source_type).
      db.execute('''
CREATE TABLE occurrence_cache (
  id TEXT NOT NULL PRIMARY KEY,
  event_id TEXT NOT NULL,
  title TEXT,
  color_id TEXT,
  start_utc INTEGER NOT NULL,
  end_utc INTEGER NOT NULL,
  day_key TEXT NOT NULL
);
''');
      db.execute(
        "INSERT INTO calendars (id, name, created_at, updated_at) VALUES ('c1','Cal',1,1);",
      );
      db.execute(
        "INSERT INTO tasks (id, title, rrule, due_date, created_at, updated_at) VALUES ('t1','Task','FREQ=DAILY','2026-01-01',1,1);",
      );
      db.execute('PRAGMA user_version = 6;');
    } finally {
      db.close();
    }

    final migrated = AppDatabase.forTesting(NativeDatabase(File(path)));
    try {
      expect(migrated.schemaVersion, 13);

      final tos = await migrated
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='task_occurrence_states'",
          )
          .get();
      expect(tos, isNotEmpty);
      final tosIdx = await migrated
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_task_occurrence_states_series_date'",
          )
          .get();
      expect(tosIdx, isNotEmpty);

      final taskCols = await migrated
          .customSelect('PRAGMA table_info(tasks)')
          .get();
      final taskNames = taskCols.map((r) => r.read<String>('name')).toSet();
      expect(
        taskNames,
        containsAll([
          'google_account',
          'microsoft_account',
          'planned_date',
          'planned_start',
          'planned_end',
          'series_id',
          'recurrence_key',
          'reminders',
        ]),
      );

      final occCols = await migrated
          .customSelect('PRAGMA table_info(occurrence_cache)')
          .get();
      final occNames = occCols.map((r) => r.read<String>('name')).toSet();
      expect(occNames, contains('source_type'));

      final task = await migrated
          .customSelect(
            "SELECT series_id, recurrence_key FROM tasks WHERE id = 't1'",
          )
          .getSingle();
      expect(task.read<String?>('series_id'), 't1');
      expect(task.read<String?>('recurrence_key'), '2026-01-01');

      final idx = await migrated
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_occurrence_cache_day'",
          )
          .get();
      expect(idx, isNotEmpty);
    } finally {
      await migrated.close();
    }
  });
}
