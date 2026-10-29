import 'package:ephemeron/features/search/presentation/search_screen.dart';
import 'package:ephemeron/features/settings/data/settings_repository.dart';
import 'package:ephemeron/l10n/src/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('search screen localizes titles', (WidgetTester tester) async {
    for (final entry in {'en': 'Search', 'pt': 'Buscar'}.entries) {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: Locale(entry.key),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SearchScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(entry.value), findsOneWidget);
    }
  });

  test('locale code defaults to system and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = SettingsRepository(await SharedPreferences.getInstance());
    expect(repo.localeCode, 'system');
    await repo.setLocaleCode('pt');
    expect(repo.localeCode, 'pt');
  });
}
