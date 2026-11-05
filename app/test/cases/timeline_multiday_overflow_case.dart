import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:ephemeron/core/db/db_provider.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/habit_repository.dart';
import 'package:ephemeron/data/repositories/occurrence_repository.dart';
import 'package:ephemeron/features/calendar/application/calendar_providers.dart';
import 'package:ephemeron/features/calendar/application/calendar_state.dart';
import 'package:ephemeron/features/calendar/presentation/timeline/timeline_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

Future<void> _seed(AppDatabase db) async {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  await db
      .into(db.calendars)
      .insert(
        CalendarsCompanion.insert(
          id: 'cal1',
          name: 'c',
          createdAt: now,
          updatedAt: now,
        ),
      );
  final day = DateTime.now();
  final start = DateTime(day.year, day.month, day.day, 10).toUtc();
  await db
      .into(db.events)
      .insert(
        EventsCompanion.insert(
          id: 'e1',
          calendarId: 'cal1',
          title: const Value(
            'A very long event title that should not overflow the grid',
          ),
          startUtc: Value(start.millisecondsSinceEpoch),
          endUtc: Value(
            start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
          ),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

CalendarWindow _window(DateTime anchor, int dayCount) => CalendarWindow(
  anchor: anchor,
  view: dayCount == 1 ? CalendarViewKind.day : CalendarViewKind.multiDay,
  dayCount: dayCount,
);

Future<void> _pump(
  WidgetTester tester,
  AppDatabase db,
  DateTime anchor,
  int dayCount,
) async {
  final window = _window(anchor, dayCount);
  await OccurrenceRepository(
    db,
  ).rebuildWindow(windowStartUtc: window.fromUtc, windowEndUtc: window.toUtc);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        calendarStateProvider.overrideWith(() => _FixedWindow(window)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: TimelineView(anchor: anchor, dayCount: dayCount),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _tearDown(WidgetTester tester, AppDatabase db) async {
  await db.close();
  await tester.pumpWidget(Container());
  await tester.pump();
}

class _FixedWindow extends CalendarState {
  _FixedWindow(this.window);
  final CalendarWindow window;
  @override
  CalendarWindow build() => window;
}

void main() {
  testWidgets('7-day 320dp multi-day timeline does not overflow', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = _db();
    final repo = HabitRepository(db);
    await repo.createHabit(
      name: 'A very long habit name that should not overflow',
      frequency: 'daily',
      startDate: '2020-01-01',
      reminderTime: '10:00',
      goalAmount: 4,
      unit: 'pages',
    );
    await repo.createHabit(
      name: 'Another overlapping long habit name',
      frequency: 'daily',
      startDate: '2020-01-01',
      reminderTime: '10:00',
    );
    await _seed(db);
    final anchor = DateTime.now();
    await _pump(tester, db, anchor, 7);
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), null);
    await _tearDown(tester, db);
  });
}
