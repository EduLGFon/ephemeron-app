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
    PendingOperations,
    Drafts,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 11;

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
      if (from < 5) {
        await m.addColumn(countdowns, countdowns.alarmPreset);
        await m.addColumn(alarmsIndex, alarmsIndex.kind);
        await m.addColumn(alarmsIndex, alarmsIndex.title);
        await m.addColumn(alarmsIndex, alarmsIndex.preset);
      }
      if (from < 6) {
        await m.addColumn(tasks, tasks.reminders);
        await m.addColumn(focusSessions, focusSessions.alarmPreset);
      }
      if (from < 7) {
        await m.deleteTable('occurrence_cache');
        await m.createTable(occurrenceCache);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_occurrence_cache_day ON occurrence_cache(day_key);',
        );
      }
      if (from < 8) {
        await m.createTable(pendingOperations);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_pending_operations_scheduled ON pending_operations(scheduled_at);',
        );
      }
      if (from < 9) {
        await m.addColumn(events, events.googleAccount);
        await m.addColumn(tasks, tasks.googleAccount);
        // Link existing rows to their parent calendar/list account.
        await customStatement(
          'UPDATE events SET google_account = '
          '(SELECT google_account FROM calendars '
          'WHERE calendars.id = events.calendar_id) '
          'WHERE google_account IS NULL;',
        );
        await customStatement(
          'UPDATE tasks SET google_account = '
          '(SELECT google_account FROM task_lists '
          'WHERE task_lists.id = tasks.list_id) '
          'WHERE google_account IS NULL;',
        );
      }
      if (from < 10) {
        await m.addColumn(tasks, tasks.plannedDate);
      }
      if (from < 11) {
        await m.addColumn(tasks, tasks.plannedStart);
        await m.addColumn(tasks, tasks.plannedEnd);
        await m.addColumn(tasks, tasks.seriesId);
        await m.addColumn(tasks, tasks.recurrenceKey);
        await m.addColumn(occurrenceCache, occurrenceCache.sourceType);
        await customStatement(
          "UPDATE tasks SET series_id = id, recurrence_key = COALESCE(planned_date, due_date) WHERE rrule IS NOT NULL AND rrule <> '';",
        );
        await m.deleteTable('occurrence_cache');
        await m.createTable(occurrenceCache);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_occurrence_cache_day ON occurrence_cache(day_key);',
        );
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
    'CREATE INDEX IF NOT EXISTS idx_pending_operations_scheduled ON pending_operations(scheduled_at);',
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
