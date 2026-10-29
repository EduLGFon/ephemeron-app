import 'package:drift/native.dart';
import 'package:ephemeron/core/db/db_provider.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/habit_repository.dart';
import 'package:ephemeron/domain/habits/date_key.dart';
import 'package:ephemeron/features/habits/presentation/habits_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('habit complete writes today log', (WidgetTester tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = HabitRepository(db);
    final id = await repo.createHabit(name: 'Read', startDate: '2026-01-01');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: HabitsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Read'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.pump();
    final today = habitDateKey(DateTime.now());
    expect((await repo.logFor(id, today))?.done, isTrue);
    // Close the db and unmount inside the test body so Drift's
    // stream-close timer fires before the pending-timer check.
    await db.close();
    await tester.pumpWidget(Container());
    await tester.pump();
  });
}
