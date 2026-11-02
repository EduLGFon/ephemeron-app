import 'package:drift/native.dart';
import 'package:ephemeron/core/db/db_provider.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/countdown_repository.dart';
import 'package:ephemeron/features/countdowns/presentation/countdowns_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('countdown appears in upcoming', (WidgetTester tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = CountdownRepository(db);
    final nextYear = DateTime.now().year + 1;
    await repo.createCountdown(title: 'Trip', targetDate: '$nextYear-06-01');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: CountdownsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Trip'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    // Close the db and unmount inside the test body so Drift's
    // stream-close timer fires before the pending-timer check.
    await db.close();
    await tester.pumpWidget(Container());
    await tester.pump();
  });
}
