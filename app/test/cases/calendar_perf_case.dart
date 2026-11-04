// Calendar cache range: coverage checks and provider stability while
// navigating inside an already materialized range.
import 'package:ephemeron/features/calendar/application/calendar_providers.dart';
import 'package:ephemeron/features/calendar/application/calendar_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('range coverage includes fully contained windows', () {
    final built = CalendarRange(
      fromUtc: DateTime.utc(2026, 3, 1),
      toUtc: DateTime.utc(2026, 3, 10),
    );
    final inside = CalendarRange(
      fromUtc: DateTime.utc(2026, 3, 2),
      toUtc: DateTime.utc(2026, 3, 9),
    );
    final edge = CalendarRange(
      fromUtc: DateTime.utc(2026, 3, 1),
      toUtc: DateTime.utc(2026, 3, 10),
    );
    final outside = CalendarRange(
      fromUtc: DateTime.utc(2026, 3, 2),
      toUtc: DateTime.utc(2026, 3, 11),
    );

    expect(built.covers(inside), isTrue);
    expect(built.covers(edge), isTrue);
    expect(built.covers(outside), isFalse);
  });

  test('selecting another day in the month view keeps the cache range', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(calendarStateProvider.notifier);
    notifier.restore(CalendarViewKind.month, DateTime(2026, 3, 10));
    final before = container.read(calendarCacheRangeProvider);
    var changes = 0;
    container.listen(calendarCacheRangeProvider, (_, _) => changes++);

    notifier.goTo(DateTime(2026, 3, 18));

    expect(container.read(calendarCacheRangeProvider), before);
    expect(changes, 0);
  });

  test('day swipes inside the buffer keep the cache range', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(calendarStateProvider.notifier);
    notifier.restore(CalendarViewKind.day, DateTime(2026, 3, 10));
    final before = container.read(calendarCacheRangeProvider);
    var changes = 0;
    container.listen(calendarCacheRangeProvider, (_, _) => changes++);

    notifier.shift(calendarDayBufferDays);
    expect(container.read(calendarCacheRangeProvider), before);
    expect(changes, 0);

    // One more day falls outside the built range and must request a rebuild.
    notifier.shift(1);
    expect(container.read(calendarCacheRangeProvider), isNot(before));
    expect(changes, 1);
  });
}
