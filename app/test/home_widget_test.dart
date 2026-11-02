import 'package:ephemeron/data/services/home_widget_service.dart';
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
}
