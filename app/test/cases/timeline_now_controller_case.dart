import 'package:ephemeron/features/calendar/presentation/timeline/timeline_now_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('refresh updates now and notifies listeners', () {
    var instant = DateTime.utc(2026, 11, 3, 9);
    final controller = TimelineNowController(clock: () => instant);
    addTearDown(controller.dispose);
    expect(controller.now, instant);

    var notifications = 0;
    controller.addListener(() => notifications++);

    instant = instant.add(const Duration(minutes: 5));
    controller.refresh();

    expect(controller.now, instant);
    expect(notifications, 1);
  });
}
