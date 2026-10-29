import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ephemeron/features/settings/data/settings_repository.dart';

void main() {
  test('settings repository defaults and round trips', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final repo = SettingsRepository(prefs);
    expect(repo.brightness, 'light');
    expect(repo.navOrder, [0, 1, 2, 3, 4, 5, 6]);
    await repo.setBrightness('dark');
    await repo.setNavOrder([6, 5, 4, 3, 2, 1, 0]);
    expect(repo.brightness, 'dark');
    expect(repo.navOrder, [6, 5, 4, 3, 2, 1, 0]);
  });
}