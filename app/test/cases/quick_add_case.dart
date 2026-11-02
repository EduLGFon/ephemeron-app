import 'package:ephemeron/domain/parsing/quick_add_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shorthands extracted, rest parsed for date', () {
    final p = parseQuickAdd(
      'Buy milk #groceries ~home -p1 tomorrow 9h',
      now: DateTime(2026, 3, 2, 8),
    );
    expect(p.title, 'Buy milk');
    expect(p.tags, ['groceries']);
    expect(p.list, 'home');
    expect(p.priority, 4);
    expect(p.due, DateTime(2026, 3, 3, 9));
  });

  test('plain title stays intact', () {
    final p = parseQuickAdd('Read a book', now: DateTime(2026, 3, 2, 8));
    expect(p.title, 'Read a book');
    expect(p.tags, isEmpty);
    expect(p.priority, 0);
    expect(p.due, isNull);
  });

  test('recurrence phrases produce rrule', () {
    final p = parseQuickAdd('Gym todo dia 8h', now: DateTime(2026, 3, 2, 8));
    expect(p.rrule, 'FREQ=DAILY');
    expect(p.due, DateTime(2026, 3, 2, 8));
  });
}
