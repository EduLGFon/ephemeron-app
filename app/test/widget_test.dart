import 'package:drift/native.dart';
import 'package:ephemeron/core/db/db_provider.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ephemeron/main.dart';

void main() {
  testWidgets('app builds', timeout: const Timeout(Duration(minutes: 3)), (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const EphemeronApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
    // Unmount first so every Riverpod stream subscription is cancelled,
    // then pump twice: the first flushes the cancellations, the second
    // fires drift's stream-cache timers. db.close() waits on those timers
    // and deadlocks if they are still pending (they only run on pump).
    await tester.pumpWidget(Container());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await db.close();
    await tester.pump();
  });
}
