import 'package:ephemeron/data/services/home_widget_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home widget catalog is non-empty', () {
    expect(homeWidgets, isNotEmpty);
    expect(homeWidgets.length, greaterThan(40));
  });

  test('collection widget definitions exist', () {
    final prefixes = homeWidgets.map((w) => w.keyPrefix).toSet();
    expect(prefixes.contains('pending_tasks_collection'), isTrue);
    expect(prefixes.contains('day_agenda_collection'), isTrue);
  });
}