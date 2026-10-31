// Backend changeset sync suite: push clears dirty/drains outbox,
// pull merges with LWW, dirty rows win, cursors advance, offline is safe.
// Google data never enters this engine (habits/focus tables only).
import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/remote/backend_sync_api.dart';
import 'package:ephemeron/data/repositories/focus_repository.dart';
import 'package:ephemeron/data/repositories/habit_repository.dart';
import 'package:ephemeron/features/auth/data/backend_auth.dart';
import 'package:ephemeron/features/sync/data/backend_sync_engine.dart';
import 'package:ephemeron/features/sync/data/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'backend_auth_test.dart' show FakeBackend, MemoryTokenStore;
import 'sync_engine_test.dart' show FakeGoogle;

class FakeSyncServer implements BackendSyncApi {
  List<Map<String, dynamic>> pushedHabits = [];
  List<Map<String, dynamic>> pushedLogs = [];
  List<Map<String, dynamic>> pushedFocus = [];
  List<Map<String, dynamic>> remoteHabits = [];
  List<Map<String, dynamic>> remoteLogs = [];
  List<Map<String, dynamic>> remoteFocus = [];
  int? lastSince;

  @override
  Future<void> push({
    required List<Map<String, dynamic>> habits,
    required List<Map<String, dynamic>> habitLogs,
    required List<Map<String, dynamic>> focusSessions,
  }) async {
    pushedHabits.addAll(habits);
    pushedLogs.addAll(habitLogs);
    pushedFocus.addAll(focusSessions);
  }

  @override
  Future<BackendPull> pull(int sinceMs) async {
    lastSince = sinceMs;
    return BackendPull(
      habits: remoteHabits
          .where((m) => (m['updatedAt'] as int) > sinceMs)
          .toList(),
      habitLogs: remoteLogs
          .where((m) => (m['updatedAt'] as int) > sinceMs)
          .toList(),
      focusSessions: remoteFocus
          .where((m) => (m['updatedAt'] as int) > sinceMs)
          .toList(),
    );
  }
}

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

BackendSyncEngine _engine(
  AppDatabase db,
  FakeSyncServer server, {
  FakeBackend? backend,
}) {
  final fake = backend ?? FakeBackend();
  fake.storedRefresh ??= 'refresh';
  final auth = BackendAuth(
    client: fake,
    tokenStore: MemoryTokenStore()..token = 'refresh',
  );
  return BackendSyncEngine(db, auth, apiFactory: (_) => server);
}

Map<String, dynamic> _remoteHabit(String id, int updatedAt) => {
  'id': id,
  'name': 'Remote',
  'frequency': 'daily',
  'updatedAt': updatedAt,
};

void main() {
  test('push clears dirty and drains habit outbox rows', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = HabitRepository(db);
    final server = FakeSyncServer();
    final engine = _engine(db, server);
    final id = await repo.createHabit(name: 'Read');
    await engine.syncNow();
    expect(engine.status, SyncStatus.synced);
    expect(server.pushedHabits.map((m) => m['id']), contains(id));
    final habit = await (db.select(
      db.habits,
    )..where((h) => h.id.equals(id))).getSingle();
    expect(habit.dirty, isFalse);
    final outbox = await db.select(db.outbox).get();
    expect(outbox, isEmpty);
  });

  test('google engine leaves habit outbox rows alone', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = HabitRepository(db);
    await repo.createHabit(name: 'Read');
    final engine = SyncEngine(db, clientFactory: () => FakeGoogle());
    await engine.syncNow();
    expect(engine.status, SyncStatus.synced);
    expect(await db.select(db.outbox).get(), isNotEmpty);
  });

  test('pull inserts remote rows and advances the cursor', () async {
    final db = _db();
    addTearDown(db.close);
    final server = FakeSyncServer()
      ..remoteHabits = [_remoteHabit('h1', 1000)]
      ..remoteLogs = [
        {
          'id': 'l1',
          'habitId': 'h1',
          'dayKey': '2026-03-08',
          'done': true,
          'updatedAt': 1001,
        },
      ]
      ..remoteFocus = [
        {'id': 'f1', 'startUtc': 900, 'updatedAt': 1002},
      ];
    final engine = _engine(db, server);
    await engine.syncNow();
    expect(
      await (db.select(
        db.habits,
      )..where((h) => h.id.equals('h1'))).getSingleOrNull(),
      isNotNull,
    );
    expect(
      await (db.select(
        db.habitLogs,
      )..where((l) => l.id.equals('l1'))).getSingleOrNull(),
      isNotNull,
    );
    expect(
      await (db.select(
        db.focusSessions,
      )..where((f) => f.id.equals('f1'))).getSingleOrNull(),
      isNotNull,
    );
    await engine.syncNow();
    expect(server.lastSince, 1002);
  });

  test('pull never overwrites a locally dirty habit', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = HabitRepository(db);
    final server = FakeSyncServer();
    final id = await repo.createHabit(name: 'Local');
    server.remoteHabits = [
      {..._remoteHabit(id, 9999999999999), 'name': 'Remote'},
    ];
    await _engine(db, server).syncNow();
    final habit = await (db.select(
      db.habits,
    )..where((h) => h.id.equals(id))).getSingle();
    expect(habit.name, 'Local');
    expect(
      server.pushedHabits.where((m) => m['id'] == id).single['name'],
      'Local',
    );
  });

  test('offline without a token pushes nothing', () async {
    final db = _db();
    addTearDown(db.close);
    final auth = BackendAuth(
      client: FakeBackend(),
      tokenStore: MemoryTokenStore(),
    );
    final server = FakeSyncServer();
    final engine = BackendSyncEngine(db, auth, apiFactory: (_) => server);
    await engine.syncNow();
    expect(engine.status, SyncStatus.offline);
    expect(server.pushedHabits, isEmpty);
  });

  test('focus sessions push via cursor', () async {
    final db = _db();
    addTearDown(db.close);
    final focus = FocusRepository(db);
    final server = FakeSyncServer();
    final id = await focus.startSession(durationMin: 25);
    await focus.finishSession(id);
    await _engine(db, server).syncNow();
    expect(server.pushedFocus.map((m) => m['id']), contains(id));
  });
}
