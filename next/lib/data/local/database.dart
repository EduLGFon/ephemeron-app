import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Lists,
    Tags,
    Tasks,
    TaskTags,
    EventTags,
    Habits,
    HabitLogs,
    FocusSessions,
    Countdowns,
    NoteFolders,
    Notes,
    CachedCalendarEvents,
    CustomSmartLists,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? connection])
      : super(connection ?? _openConnection());

  @override
  int get schemaVersion => 14;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await into(lists).insert(
            ListsCompanion.insert(
              name: 'Inbox',
              isInbox: const Value(true),
            ),
          );
        },
        onUpgrade: (m, from, to) async {
          // No-op for fresh DB; keep simple.
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