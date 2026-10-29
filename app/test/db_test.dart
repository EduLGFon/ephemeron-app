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

  test('schema version is 1', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    expect(db.schemaVersion, 1);
    await db.close();
  });
}
