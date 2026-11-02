import 'package:flutter_test/flutter_test.dart';
import 'package:ephemeron/domain/parsing/natural_date_parser.dart';

void main() {
  final now = DateTime(2026, 1, 5, 10); // Monday
  test('amanha 15h', () {
    final p = parseNatural('comprar leite amanha 15h', now: now);
    expect(p.due!.day, 6);
    expect(p.due!.hour, 15);
    expect(p.title, 'comprar leite');
  });
  test('next friday 9am', () {
    final p = parseNatural('meeting next friday 9am', now: now);
    expect(p.due!.weekday, DateTime.friday);
    expect(p.due!.hour, 9);
  });
  test('in 2 hours', () {
    final p = parseNatural('call in 2 hours', now: now);
    expect(p.due!.hour, 12);
  });
  test('every monday', () {
    final p = parseNatural('gym every monday', now: now);
    expect(p.rrule, 'FREQ=WEEKLY;BYDAY=MO');
  });
  test('todo dia 8h', () {
    final p = parseNatural('remedio todo dia 8h', now: now);
    expect(p.rrule, 'FREQ=DAILY');
    expect(p.due!.hour, 8);
  });
}
