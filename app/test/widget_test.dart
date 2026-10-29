import 'package:drift/native.dart';
import 'package:ephemeron/core/db/db_provider.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ephemeron/main.dart';

void main() {
  testWidgets('app builds', (WidgetTester tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const EphemeronApp(),
    ));
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
    // Close the db and unmount inside the test so Drift's stream-close
    // timer fires before the framework's pending-timer check.
    await db.close();
    await tester.pumpWidget(Container());
    await tester.pump();
  });
}
