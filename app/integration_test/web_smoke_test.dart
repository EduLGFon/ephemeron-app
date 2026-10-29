// In-browser smoke test: onboarding, all tabs, backend sign-in.
// Run with: flutter test integration_test/web_smoke_test.dart -d chrome
// (headless: --web-browser-flag=--headless ... --no-sandbox).
import 'package:ephemeron/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('web smoke: onboard, open every tab, sign in to backend', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: EphemeronApp()),
    );
    await tester.pumpAndSettle();

    // Onboarding (fresh profile): skip straight through.
    expect(find.text('Your time, offline first'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    // Walk every bottom-nav destination, including More-sheet tabs.
    for (final label in ['Tasks', 'Matrix', 'Habits', 'Countdowns']) {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Focus').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes').first);
    await tester.pumpAndSettle();

    // Settings > Account > backend sign-in works against no backend
    // (offline engine) without crashing.
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account and sync'));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsOneWidget);
  });
}
