import 'package:ephemeron/features/settings/data/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('onboarding flag defaults false and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = SettingsRepository(await SharedPreferences.getInstance());
    expect(repo.onboarded, isFalse);
    await repo.setOnboarded();
    expect(repo.onboarded, isTrue);
  });
}
