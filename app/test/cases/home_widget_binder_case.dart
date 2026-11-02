import 'package:drift/native.dart';
import 'package:ephemeron/core/db/db_provider.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/services/home_widget_data_binder.dart';
import 'package:ephemeron/data/services/home_widget_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encodeItems produces JSON array', () {
    final out = HomeWidgetService.encodeItems([
      {'id': '1', 'title': 'a'},
      {'id': '2', 'title': 'b'},
    ]);
    expect(out, '[{"id":"1","title":"a"},{"id":"2","title":"b"}]');
  });

  test('binder refreshAll does not throw', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await container.read(homeWidgetDataBinderProvider).refreshAll();
  });
}
