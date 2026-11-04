import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:ephemeron/core/db/db_provider.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/focus_repository.dart';
import 'package:ephemeron/features/focus/presentation/focus_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stopwatch start stores no target end and stopwatch phase', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = FocusRepository(db);

    final id = await repo.startSession();

    final session = await repo.currentSession();
    expect(session?.id, id);
    expect(session?.phase, 'stopwatch');
    expect(session?.targetEndUtc, isNull);

    await repo.finishSession(id);
    expect(await repo.currentSession(), isNull);
  });

  testWidgets('stopwatch counts up and finishes from the screen', (
    WidgetTester tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('ephemeron/alarms'),
          (call) async => null,
        );
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = FocusRepository(db);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final id = newId();
    await db
        .into(db.focusSessions)
        .insert(
          FocusSessionsCompanion.insert(
            id: id,
            startUtc: now - const Duration(seconds: 125).inMilliseconds,
            phase: const Value('stopwatch'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: FocusScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.bySemanticsLabel(RegExp('Focus elapsed time: 02:')),
      findsOneWidget,
    );
    expect(find.textContaining('Time is up'), findsNothing);
    expect(find.text('Finish'), findsOneWidget);

    await tester.tap(find.text('Finish'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(await repo.currentSession(), isNull);
    final finished = await (db.select(
      db.focusSessions,
    )..where((f) => f.id.equals(id))).getSingle();
    expect(finished.endUtc, isNotNull);

    // Close the db and unmount inside the test body so Drift's
    // stream-close timer fires before the pending-timer check.
    await db.close();
    await tester.pumpWidget(Container());
    await tester.pump();
  });
}
