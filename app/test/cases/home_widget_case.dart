import 'package:ephemeron/data/services/home_widget_service.dart';
import 'package:ephemeron/data/services/home_widget_support.dart';
import 'package:ephemeron/data/services/widget_image_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('home widget catalog is non-empty', () {
    expect(homeWidgets, isNotEmpty);
    expect(homeWidgets.length, greaterThan(40));
  });

  test('collection widget definitions exist', () {
    final prefixes = homeWidgets.map((w) => w.keyPrefix).toSet();
    expect(prefixes.contains('pending_tasks_collection'), isTrue);
    expect(prefixes.contains('day_agenda_collection'), isTrue);
  });

  test('updates skip silently without a widget host', () async {
    const channel = MethodChannel('home_widget');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw MissingPluginException(
            'No implementation found for method ${call.method} '
            'on channel home_widget',
          );
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final service = HomeWidgetService();
    await service.updateByPrefix(
      keyPrefix: 'pending_tasks',
      title: 't',
      body: 'b',
    );
    await service.updateCollection(
      keyPrefix: 'pending_tasks_collection',
      provider: 'PendingTasksCollectionProvider',
      items: const [],
    );
    await service.refreshAll();
  });

  test('unsupported platforms skip channel calls entirely', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(isHomeWidgetSupported, isFalse);
    // No mock handler: any channel call would throw MissingPluginException.
    final service = HomeWidgetService();
    await service.updateByPrefix(
      keyPrefix: 'pending_tasks',
      title: 't',
      body: 'b',
    );
    await service.updateCollection(
      keyPrefix: 'pending_tasks_collection',
      provider: 'PendingTasksCollectionProvider',
      items: const [],
    );
    await service.refreshAll();
  });

  test('image renders return null without a widget host', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final images = WidgetImageService();
    expect(
      await images.renderMonthGrid(
        year: 2026,
        month: 11,
        eventDays: const {2},
        today: 2,
      ),
      isNull,
    );
    expect(
      await images.renderHeatmap(done: const {}, end: DateTime(2026, 11, 2)),
      isNull,
    );
    expect(
      await images.renderWeekBars(minutes: const [1, 2, 3, 4, 5, 6, 7]),
      isNull,
    );
    expect(
      await images.renderWeekCalendar(
        days: const [],
        now: DateTime(2026, 11, 2),
      ),
      isNull,
    );
  });
}
