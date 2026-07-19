import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'core/routing/app_router.dart';
import 'core/settings/app_settings_provider.dart';
import 'core/settings/power_saving_manager.dart';
import 'core/settings/shared_preferences_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_engine_provider.dart';

import 'features/alarms/application/alarm_action_manager_provider.dart';
import 'features/alarms/application/alarm_scheduler_provider.dart';
import 'features/auth/google/google_auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'features/countdown/application/countdown_providers.dart';
import 'features/habits/application/habit_providers.dart';
import 'features/sync/application/sync_service.dart';

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
    // Fire-and-forget: kicks off channel setup/timezone resolution at
    // startup without blocking the first frame on it. Permission prompts
    // are a separate, deliberately-not-automatic step — see
    // AlarmScheduler.requestPermissions's doc comment.
    ref.read(alarmSchedulerInitProvider);
    // Catches up weekly/interval habit reminders whose last-computed
    // one-shot occurrence already fired — see HabitRepository
    // .refreshOneShotAlarms's doc comment for why daily habits don't
    // need this (they're genuinely OS-recurring).
    ref.read(habitAlarmsRefreshProvider);
    // Same idea for yearly countdowns rolling forward past their date.
    ref.read(countdownAlarmsRefreshProvider);
    // Handles notification done/snooze actions while the app is alive.
    ref.read(alarmActionManagerProvider);
    // Listens to app lifecycle changes to refresh battery state
    ref.read(powerSavingManagerProvider);
    // Initialize Google Auth — this silently restores a previous session
    // so Calendar/Tasks sync work immediately without visiting auth screen.
    ref.read(googleAuthInitProvider);
    // Initialize sync service (kick off background periodic timer based on settings)
    ref.read(syncServiceProvider);
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
        // Remove splash screen now that we have our first frame ready
        FlutterNativeSplash.remove();
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
