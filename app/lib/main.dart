import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ephemeron/l10n/src/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router/app_router.dart';
import 'core/security/app_lock.dart';
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
    final localeCode = repo?.localeCode ?? 'system';
    final locked = repo?.biometricLock ?? false;

    final app = MaterialApp.router(
      title: 'Ephemeron',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(
        primary: primary,
        background: background,
        brightness: brightness,
      ),
      locale: localeCode == 'system' ? null : Locale(localeCode),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    );
    if (!locked) return app;
    return _LockGate(ref: ref, child: app);
  }
}

/// Full-screen gate shown when biometric app lock is on. Stays locked
/// until authentication succeeds; unsupported devices pass through.
class _LockGate extends StatefulWidget {
  const _LockGate({required this.ref, required this.child});

  final Widget child;
  final WidgetRef ref;

  @override
  State<_LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<_LockGate> {
  bool _unlocked = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryUnlock());
  }

  Future<void> _tryUnlock() async {
    if (_busy || _unlocked || !mounted) return;
    setState(() => _busy = true);
    // On devices without biometric/device-credential support, the lock cannot
    // be used: clear the stale setting and pass through.
    if (!await AppLock.isSupported()) {
      try {
        final repo = await widget.ref.read(settingsRepositoryProvider.future);
        await repo.setBiometricLock(false);
        widget.ref.invalidate(settingsRepositoryProvider);
      } catch (_) {
        // Best-effort cleanup; never block unlock.
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _unlocked = true;
      });
      return;
    }
    final ok = await AppLock.authenticate();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _unlocked = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 12),
              const Text('Ephemeron is locked'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _tryUnlock,
                icon: const Icon(Icons.fingerprint),
                label: Text(_busy ? 'Waiting...' : 'Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
