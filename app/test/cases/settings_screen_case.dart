import 'package:ephemeron/features/settings/data/settings_repository.dart';
import 'package:ephemeron/features/settings/presentation/settings_screen.dart';
import 'package:ephemeron/l10n/src/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _settingsApp() {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SettingsScreen(),
    ),
  );
}

void main() {
  test('theme and accessibility settings round trip', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = SettingsRepository(await SharedPreferences.getInstance());

    expect(repo.primaryColorHex, isNull);
    expect(repo.backgroundColorHex, isNull);
    expect(repo.localeCode, 'system');
    expect(repo.powerSavingMode, PowerSavingMode.auto);
    expect(repo.haptics, isTrue);

    await repo.setPrimaryColorHex('#112233');
    await repo.setBackgroundColorHex('#fbf7f0');
    await repo.setBrightness('amoled');
    await repo.setLocaleCode('pt');
    await repo.setPowerSavingMode(PowerSavingMode.off);
    await repo.setReduceAnimations(true);
    await repo.setHaptics(false);

    expect(repo.primaryColorHex, '#112233');
    expect(repo.backgroundColorHex, '#fbf7f0');
    expect(repo.brightness, 'amoled');
    expect(repo.localeCode, 'pt');
    expect(repo.powerSavingMode, PowerSavingMode.off);
    expect(repo.reduceAnimations, isTrue);
    expect(repo.haptics, isFalse);
  });

  testWidgets('color presets and brightness show the current selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'settings.primaryColor': '#E53935',
      'settings.backgroundColor': '#121212',
      'settings.brightness': 'dark',
    });
    await tester.pumpWidget(_settingsApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('primary-selected-#e53935')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('background-selected-#121212')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('brightness-dark')))
          .selected,
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('primary-color-#00897b')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('primary-selected-#00897b')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('primary-selected-#e53935')),
      findsNothing,
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        'settings.primaryColor',
      ),
      '#00897b',
    );

    await tester.tap(find.byKey(const ValueKey('brightness-light')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('brightness-light')))
          .selected,
      isTrue,
    );
    expect(
      (await SharedPreferences.getInstance()).getString('settings.brightness'),
      'light',
    );
  });

  testWidgets('custom hex fields show values and keep validation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'settings.primaryColor': '#112233',
    });
    await tester.pumpWidget(_settingsApp());
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('primary-hex-field'));
    expect(tester.widget<TextField>(field).controller?.text, '#112233');

    await tester.enterText(field, 'not-a-color');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('Enter a valid hex like #RRGGBB.'), findsOneWidget);

    await tester.enterText(field, '#445566');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(field).controller?.text, '#445566');
    expect(find.text('Enter a valid hex like #RRGGBB.'), findsNothing);
    expect(
      (await SharedPreferences.getInstance()).getString(
        'settings.primaryColor',
      ),
      '#445566',
    );
  });

  testWidgets('settings screen does not overflow on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_settingsApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(ListView), const Offset(0, -2400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
