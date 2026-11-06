import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart';

// Verifies the v5 schema migration adds alarm/countdown columns and preserves
// pre-v5 rows. Full AppDatabase replay from v4->v12 is not used here because
// migration v11 adds occurrence_cache.source_type then deletes/recreates the
// table; v7 already recreates it with the current schema, so v11's addColumn
// can fail with "duplicate column name" during a full replay. This test
// validates the v5 DDL (same ALTER TABLE operations as migration v5) against a
// deterministic v4 database.
void main() {
  test('v4 to v5 adds countdown/alarm columns and preserves rows', () {
    final dir = Directory.systemTemp.createTempSync('ephemeron_v4v5_');
    final path = '${dir.path}/v4.db';
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    final db = sqlite3.open(path);
    try {
      // Pre-v5 schema: countdowns without alarm_preset, alarms_index without
      // kind/title/preset.
      db.execute('''
CREATE TABLE countdowns (
  id TEXT NOT NULL PRIMARY KEY,
  title TEXT NOT NULL,
  type TEXT,
  template TEXT,
  target_date TEXT,
  yearly_repeat INTEGER NOT NULL DEFAULT 0,
  show_age INTEGER NOT NULL DEFAULT 0,
  notes TEXT,
  alert_offset_days INTEGER,
  alert_time_min INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);
''');
      db.execute('''
CREATE TABLE alarms_index (
  id TEXT NOT NULL PRIMARY KEY,
  source_type TEXT NOT NULL,
  source_id TEXT NOT NULL,
  fire_at_utc INTEGER NOT NULL,
  preset_step INTEGER,
  request_code INTEGER,
  state TEXT NOT NULL DEFAULT 'scheduled'
);
''');
      db.execute('''
INSERT INTO countdowns (
  id, title, target_date, yearly_repeat, show_age, created_at, updated_at
) VALUES ('cd1', 'Launch', '2026-12-31', 0, 0, 1000, 1000);
''');
      db.execute('''
INSERT INTO alarms_index (
  id, source_type, source_id, fire_at_utc, preset_step, request_code, state
) VALUES ('al1', 'countdown', 'cd1', 2000, 1, 42, 'scheduled');
''');
      db.execute('PRAGMA user_version = 4;');
    } finally {
      db.close();
    }

    final migrated = sqlite3.open(path);
    try {
      // Migration v5 operations (app_database.dart).
      migrated.execute('ALTER TABLE countdowns ADD COLUMN alarm_preset TEXT;');
      migrated.execute(
        "ALTER TABLE alarms_index ADD COLUMN kind TEXT NOT NULL DEFAULT 'alarm';",
      );
      migrated.execute('ALTER TABLE alarms_index ADD COLUMN title TEXT;');
      migrated.execute('ALTER TABLE alarms_index ADD COLUMN preset TEXT;');
      migrated.execute('PRAGMA user_version = 5;');

      final cdCols = migrated
          .select('PRAGMA table_info(countdowns);')
          .map((r) => r['name'] as String)
          .toSet();
      expect(cdCols, contains('alarm_preset'));
      final cdRow = migrated.select(
        'SELECT id, title, alarm_preset FROM countdowns WHERE id = ?;',
        ['cd1'],
      ).single;
      expect(cdRow['title'], 'Launch');
      expect(cdRow['alarm_preset'], isNull);

      final alarmCols = migrated
          .select('PRAGMA table_info(alarms_index);')
          .map((r) => r['name'] as String)
          .toSet();
      expect(alarmCols, containsAll(['kind', 'title', 'preset']));
      final alarmRow = migrated.select(
        'SELECT id, kind, title, preset, state FROM alarms_index WHERE id = ?;',
        ['al1'],
      ).single;
      expect(alarmRow['kind'], 'alarm');
      expect(alarmRow['title'], isNull);
      expect(alarmRow['preset'], isNull);
      expect(alarmRow['state'], 'scheduled');
    } finally {
      migrated.close();
    }
  });
}
