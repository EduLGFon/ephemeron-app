import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ephemeron/data/drift/app_database.dart';

void main() {
  test('in-memory db creates schema and inserts calendar', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final now = DateTime.now().millisecondsSinceEpoch;
    await db
        .into(db.calendars)
        .insert(
          CalendarsCompanion.insert(
            id: 'c1',
            name: 'Main',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final rows = await db.select(db.calendars).get();
    expect(rows.length, 1);
    expect(rows.first.name, 'Main');
    await db.close();
  });

  test('fts tables exist', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final res = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='notes_fts'",
        )
        .get();
    expect(res, isNotEmpty);
    await db.close();
  });

  test('schema version is 12', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    expect(db.schemaVersion, 12);
    await db.close();
  });

  test('events and tasks carry google_account', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    for (final table in ['events', 'tasks']) {
      final cols = await db.customSelect('PRAGMA table_info($table)').get();
      expect(
        cols.map((r) => r.read<String>('name')),
        contains('google_account'),
      );
    }
    await db.close();
  });

  test('tasks carry nullable planned_date added in v10', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final cols = await db.customSelect('PRAGMA table_info(tasks)').get();
    final planned = cols.where((r) => r.read<String>('name') == 'planned_date');
    expect(planned, hasLength(1));
    expect(planned.single.read<int>('notnull'), 0);
    await db.close();
  });

  test('tasks carry v11 columns', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final cols = await db.customSelect('PRAGMA table_info(tasks)').get();
    final names = cols.map((r) => r.read<String>('name')).toSet();
    for (final c in [
      'planned_start',
      'planned_end',
      'series_id',
      'recurrence_key',
    ]) {
      expect(names, contains(c));
    }
    final occ = await db
        .customSelect('PRAGMA table_info(occurrence_cache)')
        .get();
    final occNames = occ.map((r) => r.read<String>('name')).toSet();
    expect(occNames, contains('source_type'));
    await db.close();
  });

  test('v12 adds microsoft_account columns', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    for (final table in ['calendars', 'events', 'task_lists', 'tasks']) {
      final cols = await db.customSelect('PRAGMA table_info($table)').get();
      final names = cols.map((r) => r.read<String>('name')).toSet();
      expect(names, contains('microsoft_account'));
    }
    await db.close();
  });

  test('occurrence cache day index exists', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final res = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_occurrence_cache_day'",
        )
        .get();
    expect(res, isNotEmpty);
    await db.close();
  });
}
