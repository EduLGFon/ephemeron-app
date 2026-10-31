import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:ephemeron/core/db/db_provider.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/occurrence_repository.dart';
import 'package:ephemeron/features/calendar/application/calendar_providers.dart';
import 'package:ephemeron/features/calendar/application/calendar_state.dart';
import 'package:ephemeron/features/calendar/presentation/timeline_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

Future<void> _seed(AppDatabase db, {String? tzId}) async {
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
          title: const Value('Standup'),
          startUtc: Value(start.millisecondsSinceEpoch),
          endUtc: Value(
            start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
          ),
          tzId: Value(tzId),
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

/// Mirrors widget_test.dart: close the db and unmount inside the test so
/// Drift's stream-close timer fires before the pending-timer check.
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

/// Vertical distance between two adjacent hour labels.
double _hourGap(WidgetTester tester) {
  final a = tester.getTopLeft(find.text('00:00'));
  final b = tester.getTopLeft(find.text('01:00'));
  return b.dy - a.dy;
}

Future<void> _pressZoomIn(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.equal);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.equal);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

Future<void> _pressZoomOut(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.minus);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.minus);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  test('rebuild tolerates non-IANA tz abbreviations', () async {
    final db = _db();
    addTearDown(db.close);
    await _seed(db, tzId: '-03');
    final repo = OccurrenceRepository(db);
    final anchor = DateTime.now();
    final window = _window(anchor, 1);
    final n = await repo.rebuildWindow(
      windowStartUtc: window.fromUtc,
      windowEndUtc: window.toUtc,
    );
    expect(n, 1);
  });

  testWidgets('day view shows hours, header and event', (
    WidgetTester tester,
  ) async {
    final db = _db();
    await _seed(db);
    final anchor = DateTime.now();
    await _pump(tester, db, anchor, 1);

    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('23:00'), findsOneWidget);
    expect(find.text('${anchor.day}'), findsOneWidget);
    expect(find.text('Standup'), findsOneWidget);

    // Tapping the event opens details instead of the create sheet.
    await tester.ensureVisible(find.text('Standup'));
    await tester.pump();
    await tester.tap(find.text('Standup'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Edit'), findsOneWidget);
    await _tearDown(tester, db);
  });

  testWidgets('multi-day view shows all days and scrolls', (
    WidgetTester tester,
  ) async {
    final db = _db();
    await _seed(db);
    final anchor = DateTime.now();
    await _pump(tester, db, anchor, 3);

    for (var i = 0; i < 3; i++) {
      final d = DateTime(
        anchor.year,
        anchor.month,
        anchor.day,
      ).add(Duration(days: i));
      expect(find.text('${d.day}'), findsWidgets);
    }
    expect(find.text('Standup'), findsOneWidget);

    final scroller = find.byType(SingleChildScrollView);
    expect(scroller, findsOneWidget);
    await tester.drag(scroller, const Offset(0, -300));
    await tester.pump();
    // Still renders after scrolling (hours gutter scrolls in sync).
    expect(find.text('Standup', skipOffstage: false), findsOneWidget);
    expect(find.text('00:00', skipOffstage: false), findsOneWidget);
    await _tearDown(tester, db);
  });

  testWidgets('keyboard Ctrl+= and Ctrl+- zoom the timeline', (
    WidgetTester tester,
  ) async {
    final db = _db();
    await _seed(db);
    await _pump(tester, db, DateTime.now(), 1);

    expect(_hourGap(tester), moreOrLessEquals(56));

    await _pressZoomIn(tester);
    expect(_hourGap(tester), moreOrLessEquals(56 * 1.25));

    await _pressZoomOut(tester);
    expect(_hourGap(tester), moreOrLessEquals(56));
    await _tearDown(tester, db);
  });

  testWidgets('pinch zooms the timeline', (WidgetTester tester) async {
    final db = _db();
    await _seed(db);
    await _pump(tester, db, DateTime.now(), 1);

    final before = _hourGap(tester);
    final center = tester.getCenter(find.byType(SingleChildScrollView));
    final g1 = await tester.startGesture(center + const Offset(-40, 0));
    await tester.pump();
    final g2 = await tester.startGesture(center + const Offset(40, 0));
    await tester.pump();
    await g1.moveTo(center + const Offset(-90, 0));
    await g2.moveTo(center + const Offset(90, 0));
    await tester.pump();
    expect(_hourGap(tester), greaterThan(before + 1));
    await g1.up();
    await g2.up();
    await _tearDown(tester, db);
  });
}
