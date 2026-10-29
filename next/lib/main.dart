import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'core/routing/app_router.dart';
import 'core/settings/app_settings_provider.dart';

import 'core/settings/shared_preferences_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_engine_provider.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'core/bootstrap/app_bootstrapper.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  sharedPrefs = await SharedPreferences.getInstance();
  runApp(const ProviderScope(child: EphemeronApp()));
}

class EphemeronApp extends ConsumerStatefulWidget {
  const EphemeronApp({super.key});

  @override
  ConsumerState<EphemeronApp> createState() => _EphemeronAppState();
}

class _EphemeronAppState extends ConsumerState<EphemeronApp> {
  @override
  void initState() {
    super.initState();
    ref.read(appBootstrapperProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final router = ref.watch(appRouterProvider);

    // Pre-warming of primary providers has been removed to avoid blocking the UI thread
    // during the critical first frame layout. These providers will lazy-load when their
    // respective screens are visited.

    final palette = ref.watch(themeEngineProvider);
    final isReducedMotion = settings.shouldReduceMotion;

    return MaterialApp.router(
      title: 'Ephemeron',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light, // We control the palette directly now
      theme: AppTheme.build(palette, reducedMotion: isReducedMotion),
      routerConfig: router,
      builder: (context, child) {
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
