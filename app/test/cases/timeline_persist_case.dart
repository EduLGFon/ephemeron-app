import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ephemeron/features/settings/data/settings_repository.dart';

void main() {
  test('timeline settings round trip with defaults', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repo = SettingsRepository(await SharedPreferences.getInstance());
    expect(repo.timelineScale, 1.0);
    expect(repo.timelineScrollOffset, 0.0);
    await repo.setTimelineScale(1.5);
    await repo.setTimelineScrollOffset(120.0);
    expect(repo.timelineScale, 1.5);
    expect(repo.timelineScrollOffset, 120.0);

    await repo.setTimelineScale(10.0);
    expect(repo.timelineScale, 3.0);
    await repo.setTimelineScale(-1.0);
    expect(repo.timelineScale, 1.0);
    await repo.setTimelineScrollOffset(-1.0);
    expect(repo.timelineScrollOffset, 0.0);
  });

  test('timeline settings clamp missing and negative values', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'calendar.timelineScale': -2.0,
      'calendar.timelineScrollOffset': -5.0,
    });
    final repo = SettingsRepository(await SharedPreferences.getInstance());
    expect(repo.timelineScale, 1.0);
    expect(repo.timelineScrollOffset, 0.0);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final fresh = SettingsRepository(await SharedPreferences.getInstance());
    expect(fresh.timelineScale, 1.0);
    expect(fresh.timelineScrollOffset, 0.0);
  });

  test('timeline settings survive a simulated restart', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final repo = SettingsRepository(prefs);
    await repo.setTimelineScale(2.0);
    await repo.setTimelineScrollOffset(75.5);

    // Simulate process restart by constructing a new repository instance.
    final restored = SettingsRepository(prefs);
    expect(restored.timelineScale, 2.0);
    expect(restored.timelineScrollOffset, 75.5);

    // Clamping on read: out-of-range persisted values are clamped.
    await prefs.setDouble('calendar.timelineScale', 99.0);
    await prefs.setDouble('calendar.timelineScrollOffset', -3.0);
    final clamped = SettingsRepository(prefs);
    expect(clamped.timelineScale, 3.0);
    expect(clamped.timelineScrollOffset, 0.0);

    // Note: TimelineInteraction restore logic (controller mixin) is not unit
    // tested here because it requires a widget/mixin host; the settings-repo
    // round-trip above is the core persistence contract it depends on.
  });
}
