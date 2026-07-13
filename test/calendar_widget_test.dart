import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ephemeron/data/local/database.dart';
import 'package:ephemeron/data/local/database_provider.dart';
import 'package:ephemeron/core/settings/shared_preferences_provider.dart';
import 'package:ephemeron/features/auth/google/google_auth_provider.dart';
import 'package:ephemeron/features/calendar/presentation/calendar_screen.dart';

late SharedPreferences sharedPrefs;

void main() {
  testWidgets('CalendarScreen builds and loads without error', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    sharedPrefs = await SharedPreferences.getInstance();

    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          googleAccountProvider.overrideWithValue(const AsyncValue.data(null)),
          appDatabaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(sharedPrefs),
        ],
        child: const MaterialApp(
          home: CalendarScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(CalendarScreen), findsOneWidget);

    await db.close();
  });
}
