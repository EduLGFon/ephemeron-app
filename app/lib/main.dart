import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_tokens.dart';
import 'features/settings/application/settings_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const ProviderScope(child: EphemeronApp()));
}

class EphemeronApp extends ConsumerWidget {
  const EphemeronApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsRepositoryProvider);
    final repo = settings.maybeWhen(data: (r) => r, orElse: () => null);

    final primary = repo?.primaryColorHex != null
        ? parseHex(repo!.primaryColorHex!)
        : primaryPresets.first;
    final background = repo?.backgroundColorHex != null
        ? parseHex(repo!.backgroundColorHex!)
        : backgroundPresets.first;
    final brightnessName = repo?.brightness ?? 'light';
    final brightness = AppBrightness.values.firstWhere(
      (b) => b.name == brightnessName,
      orElse: () => AppBrightness.light,
    );

    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Ephemeron',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(
        primary: primary,
        background: background,
        brightness: brightness,
      ),
      routerConfig: router,
    );
  }
}
