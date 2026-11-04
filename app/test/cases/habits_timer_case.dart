import 'package:drift/native.dart';
import 'package:ephemeron/core/db/db_provider.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/habit_repository.dart';
import 'package:ephemeron/data/services/habit_timer_store.dart';
import 'package:ephemeron/domain/habits/date_key.dart';
import 'package:ephemeron/domain/habits/habit_timer.dart';
import 'package:ephemeron/features/habits/presentation/habits_screen.dart';
import 'package:ephemeron/features/habits/application/habits_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('pure elapsed helpers', () {
    expect(isMinuteUnit('Min'), isTrue);
    expect(isMinuteUnit('MINUTES'), isTrue);
    expect(isMinuteUnit('count'), isFalse);
    expect(elapsedMinutes(const Duration(seconds: 90)), 1.5);
    expect(formatElapsed(const Duration(seconds: 3661)), '01:01:01');
    expect(formatElapsed(const Duration(seconds: 65)), '01:05');
    final e = timerElapsed(startedAtMs: 1000, nowMs: 4000);
    expect(e, const Duration(milliseconds: 3000));
  });

  test('timer store persists and clears', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final store = HabitTimerStore(prefs);
    expect(store.active.value, isNull);
    await store.start('h1', '2026-03-08', 12345);
    expect(store.active.value?.habitId, 'h1');
    final store2 = HabitTimerStore(prefs);
    expect(store2.active.value?.startedAtMs, 12345);
    await store.clear();
    expect(store.active.value, isNull);
    final store3 = HabitTimerStore(prefs);
    expect(store3.active.value, isNull);
  });

  test('plus button increment via addAmount', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = HabitRepository(db);
    final id = await repo.createHabit(
      name: 'Read',
      startDate: '2026-03-01',
      goalAmount: 10,
      unit: 'min',
      increment: 2,
    );
    final day = '2026-03-08';
    await repo.addAmount(id, day, 2);
    final log = await repo.logFor(id, day);
    expect(log?.amount, 2);
    expect(log?.done, isFalse);
    await repo.addAmount(id, day, 8);
    final log2 = await repo.logFor(id, day);
    expect(log2?.amount, 10);
    expect(log2?.done, isTrue);
  });

  testWidgets('goal habit shows plus button and increments', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = HabitRepository(db);
    final id = await repo.createHabit(
      name: 'Read',
      startDate: '2026-01-01',
      goalAmount: 10,
      unit: 'count',
      increment: 2,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          habitTimerStoreProvider.overrideWithValue(
            AsyncData(HabitTimerStore(await SharedPreferences.getInstance())),
          ),
        ],
        child: const MaterialApp(home: HabitsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Add 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Add 2'));
    await tester.pump();
    await tester.pump();
    final today = habitDateKey(DateTime.now());
    expect((await repo.logFor(id, today))?.amount, 2);
    await db.close();
    await tester.pumpWidget(Container());
    await tester.pump();
  });

  testWidgets('minute habit timer start stop', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = HabitRepository(db);
    await repo.createHabit(
      name: 'Run',
      startDate: '2026-01-01',
      goalAmount: 10,
      unit: 'min',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          habitTimerStoreProvider.overrideWithValue(
            AsyncData(HabitTimerStore(await SharedPreferences.getInstance())),
          ),
        ],
        child: const MaterialApp(home: HabitsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byIcon(Icons.play_arrow).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byIcon(Icons.stop), findsOneWidget);
    await tester.tap(find.byIcon(Icons.stop).first);
    await tester.pump();
    await tester.pump();
    final prefs = await SharedPreferences.getInstance();
    // persisted timer cleared
    expect(prefs.getString('habit_timer.habitId'), isNull);
    await db.close();
    await tester.pumpWidget(Container());
    await tester.pump();
  });

  testWidgets('second timer start shows message', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = HabitRepository(db);
    await repo.createHabit(
      name: 'Run',
      startDate: '2026-01-01',
      goalAmount: 10,
      unit: 'min',
    );
    await repo.createHabit(
      name: 'Walk',
      startDate: '2026-01-01',
      goalAmount: 10,
      unit: 'min',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          habitTimerStoreProvider.overrideWithValue(
            AsyncData(HabitTimerStore(await SharedPreferences.getInstance())),
          ),
        ],
        child: const MaterialApp(home: HabitsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(Icons.play_arrow).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    // start second
    await tester.tap(find.byIcon(Icons.play_arrow).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.text('Another habit timer is already running.'),
      findsOneWidget,
    );
    await db.close();
    await tester.pumpWidget(Container());
    await tester.pump();
  });

  testWidgets('timer start blocked on non-today day', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = HabitRepository(db);
    await repo.createHabit(
      name: 'Run',
      startDate: '2026-01-01',
      goalAmount: 10,
      unit: 'min',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          habitTimerStoreProvider.overrideWithValue(
            AsyncData(HabitTimerStore(await SharedPreferences.getInstance())),
          ),
        ],
        child: const MaterialApp(home: HabitsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // select a past day
    await tester.tap(find.byType(ChoiceChip).first);
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byIcon(Icons.play_arrow).first);
    await tester.pump();
    await tester.pump();
    expect(find.text('Timer can only start for today.'), findsOneWidget);
    await db.close();
    await tester.pumpWidget(Container());
    await tester.pump();
  });

  testWidgets('320dp trailing no overflow with timer', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = HabitRepository(db);
    await repo.createHabit(
      name: 'Run',
      startDate: '2026-01-01',
      goalAmount: 10,
      unit: 'min',
      increment: 2,
    );
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: HabitsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // start timer to show elapsed+stop
    await tester.tap(find.byIcon(Icons.play_arrow).first);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await db.close();
    await tester.pumpWidget(Container());
    await tester.pump();
  });
}
