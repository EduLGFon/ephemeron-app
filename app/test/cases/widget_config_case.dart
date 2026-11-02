import 'package:ephemeron/data/services/widget_config_store.dart';
import 'package:ephemeron/data/services/widget_image_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('config kinds cover key widget families', () {
    expect(widgetConfigKinds['PendingTasksWidgetProvider'], 'listId');
    expect(widgetConfigKinds['OneNoteWidgetProvider'], 'noteId');
    expect(widgetConfigKinds['CountdownWidgetProvider'], 'countdownId');
    expect(widgetConfigKinds['HabitStreakWidgetProvider'], 'habitId');
  });

  test('widget config store round-trips', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = WidgetConfigStore(prefs);
    expect(store.get('PendingTasksWidgetProvider'), isNull);
    await store.set('PendingTasksWidgetProvider', 'list-1');
    expect(store.get('PendingTasksWidgetProvider'), 'list-1');
    await store.set('PendingTasksWidgetProvider', null);
    expect(store.get('PendingTasksWidgetProvider'), isNull);
  });

  testWidgets('month grid image builds', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: MonthGridImage(
          year: 2026,
          month: 10,
          eventDays: {31},
          today: 31,
        ),
      ),
    );
    expect(find.text('31.'), findsOneWidget);
  });

  testWidgets('week bars image builds', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: WeekBarsImage(minutes: [10, 20, 0, 5, 30, 0, 15]),
      ),
    );
    expect(find.byType(WeekBarsImage), findsOneWidget);
  });

  test('image throttle respects 15-minute interval', () {
    const now = 1000000000000;
    expect(WidgetImageService.shouldRender(lastMs: null, nowMs: now), isTrue);
    expect(
      WidgetImageService.shouldRender(lastMs: now - 1000, nowMs: now),
      isFalse,
    );
    expect(
      WidgetImageService.shouldRender(
        lastMs: now - WidgetImageService.minRenderIntervalMs,
        nowMs: now,
      ),
      isTrue,
    );
  });
}
