import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Calendars,
    Events,
    EventAttendees,
    OccurrenceCache,
    TaskLists,
    Tasks,
    TaskTags,
    SmartLists,
    Tags,
    TagDefaults,
    HabitSections,
    Habits,
    HabitLogs,
    Countdowns,
    FocusSessions,
    Folders,
    Notes,
    NoteLinks,
    Attachments,
    AlarmsIndex,
    Outbox,
    SyncState,
    Drafts,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createIndexesAndFts(this);
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(occurrenceCache, occurrenceCache.title);
        await m.addColumn(occurrenceCache, occurrenceCache.colorId);
      }
      if (from < 3) {
        await m.addColumn(events, events.createMeet);
      }
      if (from < 4) {
        await m.addColumn(calendars, calendars.googleAccount);
        await m.addColumn(taskLists, taskLists.googleAccount);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON;');
      await customStatement('PRAGMA journal_mode = WAL;');
      await customStatement('PRAGMA synchronous = NORMAL;');
    },
  );

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'ephemeron_db',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    );
  }
}

Future<void> _createIndexesAndFts(AppDatabase db) async {
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_events_calendar_start ON events(calendar_id, start_utc);',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_events_recurring_master ON events(recurring_master_id);',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_occurrence_cache_day ON occurrence_cache(day_key);',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_tasks_list_deleted_completed_due ON tasks(list_id, deleted_at, completed_at, due_date);',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_tasks_parent ON tasks(parent_id);',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_habit_logs_habit_day ON habit_logs(habit_id, day_key);',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_focus_sessions_start ON focus_sessions(start_utc);',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_notes_folder_updated ON notes(folder_id, updated_at);',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_alarms_fire ON alarms_index(fire_at_utc);',
  );

  await db.customStatement(
    "CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(title, body, content='notes', content_rowid='rowid');",
  );
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS notes_ai AFTER INSERT ON notes BEGIN
  INSERT INTO notes_fts(rowid, title, body) VALUES (new.rowid, new.title, new.body);
END;''');
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS notes_ad AFTER DELETE ON notes BEGIN
  INSERT INTO notes_fts(notes_fts, rowid, title, body) VALUES ('delete', old.rowid, old.title, old.body);
END;''');
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS notes_au AFTER UPDATE ON notes BEGIN
  INSERT INTO notes_fts(notes_fts, rowid, title, body) VALUES ('delete', old.rowid, old.title, old.body);
  INSERT INTO notes_fts(rowid, title, body) VALUES (new.rowid, new.title, new.body);
END;''');

  await db.customStatement(
    "CREATE VIRTUAL TABLE IF NOT EXISTS tasks_fts USING fts5(title, notes, content='tasks', content_rowid='rowid');",
  );
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS tasks_ai AFTER INSERT ON tasks BEGIN
  INSERT INTO tasks_fts(rowid, title, notes) VALUES (new.rowid, new.title, new.notes);
END;''');
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS tasks_ad AFTER DELETE ON tasks BEGIN
  INSERT INTO tasks_fts(tasks_fts, rowid, title, notes) VALUES ('delete', old.rowid, old.title, old.notes);
END;''');
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS tasks_au AFTER UPDATE ON tasks BEGIN
  INSERT INTO tasks_fts(tasks_fts, rowid, title, notes) VALUES ('delete', old.rowid, old.title, old.notes);
  INSERT INTO tasks_fts(rowid, title, notes) VALUES (new.rowid, new.title, new.notes);
END;''');
}
