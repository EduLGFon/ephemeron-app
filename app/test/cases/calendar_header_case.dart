// Calendar AppBar: the clickable sync title reads "Calendar" and the current
// period sits below it, without overflowing a narrow toolbar.
import 'package:drift/native.dart';
import 'package:ephemeron/core/db/db_provider.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/occurrence_repository.dart';
import 'package:ephemeron/features/calendar/application/calendar_providers.dart';
import 'package:ephemeron/features/calendar/application/calendar_state.dart';
import 'package:ephemeron/features/calendar/presentation/calendar_screen.dart';
import 'package:ephemeron/features/sync/presentation/sync_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

class _FixedWindow extends CalendarState {
  _FixedWindow(this.window);
  final CalendarWindow window;
  @override
  CalendarWindow build() => window;
}

final _anchor = DateTime(2026, 11, 4);

Future<void> _pumpHeader(
  WidgetTester tester,
  AppDatabase db, {
  Size size = const Size(400, 800),
}) async {
  final window = CalendarWindow(anchor: _anchor, view: CalendarViewKind.month);
  await OccurrenceRepository(
    db,
  ).rebuildWindow(windowStartUtc: window.fromUtc, windowEndUtc: window.toUtc);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        calendarStateProvider.overrideWith(() => _FixedWindow(window)),
      ],
      child: const MaterialApp(home: CalendarScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _tearDown(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(Container());
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await db.close();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('header shows Calendar above the current period', (
    WidgetTester tester,
  ) async {
    final db = _db();
    await _pumpHeader(tester, db);

    expect(find.byType(SyncTitle), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SyncTitle),
        matching: find.text('Calendar'),
      ),
      findsOneWidget,
    );
    final period = DateFormat.yMMM('en_US').format(_anchor);
    final periodFinder = find.text(period);
    expect(periodFinder, findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Calendar')).dy,
      lessThan(tester.getTopLeft(periodFinder).dy),
    );
    expect(
      find.descendant(
        of: find.byType(SyncTitle),
        matching: find.byType(InkWell),
      ),
      findsOneWidget,
    );

    await _tearDown(tester, db);
  });

  testWidgets('header does not overflow a narrow toolbar', (
    WidgetTester tester,
  ) async {
    final db = _db();
    await _pumpHeader(tester, db, size: const Size(320, 640));

    expect(find.byType(SyncTitle), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _tearDown(tester, db);
  });
}
