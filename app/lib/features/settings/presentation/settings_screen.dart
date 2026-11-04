// Main settings screen: one scrollable page grouped into appearance, behavior,
// accounts and sync, security, data and widgets, and navigation.
import 'package:ephemeron/core/security/app_lock.dart';
import 'package:ephemeron/core/theme/theme_tokens.dart';
import 'package:ephemeron/l10n/src/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_screen.dart';
import '../../sync/application/sync_providers.dart';
import '../application/settings_providers.dart';
import '../data/settings_repository.dart';
import 'backup_section.dart';
import 'home_widgets_screen.dart';
import 'nav_order_sheet.dart';
import 'settings_widgets.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  SettingsRepository? _repo;
  bool _loading = true;
  bool _failed = false;

  // Local values mirror the repository so selections update immediately
  // without rebuilding the whole screen through a provider refresh.
  String _primaryHex = colorToHex(primaryPresets.first);
  String _backgroundHex = colorToHex(backgroundPresets.first);
  AppBrightness _brightness = AppBrightness.light;
  String _localeCode = 'system';
  PowerSavingMode _powerSavingMode = PowerSavingMode.auto;
  bool _reduceAnimations = false;
  bool _haptics = true;
  bool _biometricLock = false;
  bool _biometricSupported = false;
  int _syncIntervalMin = 30;
  int _backendSyncIntervalMin = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      if (!mounted) return;
      setState(() {
        _repo = repo;
        _primaryHex = _normalizedHex(
          repo.primaryColorHex,
          colorToHex(primaryPresets.first),
        );
        _backgroundHex = _normalizedHex(
          repo.backgroundColorHex,
          colorToHex(backgroundPresets.first),
        );
        _brightness = AppBrightness.values.firstWhere(
          (b) => b.name == repo.brightness,
          orElse: () => AppBrightness.light,
        );
        _localeCode = repo.localeCode;
        _powerSavingMode = repo.powerSavingMode;
        _reduceAnimations = repo.reduceAnimations;
        _haptics = repo.haptics;
        _biometricLock = repo.biometricLock;
        _syncIntervalMin = repo.syncIntervalMin;
        _backendSyncIntervalMin = repo.backendSyncIntervalMin;
        _loading = false;
      });
      // The lock switch is optional; resolve platform support in the
      // background so a slow platform channel never blocks the screen.
      _loadBiometricSupport();
      if (repo.lastRoute != '/settings') await repo.setLastRoute('/settings');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _loadBiometricSupport() async {
    try {
      final supported = await AppLock.isSupported();
      if (mounted) setState(() => _biometricSupported = supported);
    } catch (_) {
      if (mounted) setState(() => _biometricSupported = false);
    }
  }

  String _normalizedHex(String? raw, String fallback) {
    if (raw == null || !isValidHex(raw)) return fallback;
    return colorToHex(parseHex(raw));
  }

  Future<void> _persist(
    Future<void> Function(SettingsRepository repo) action,
  ) async {
    final repo = _repo;
    if (repo == null) return;
    try {
      await action(repo);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save this setting.')),
        );
      }
      return;
    }
    if (mounted) ref.invalidate(settingsRepositoryProvider);
  }

  Future<void> _selectColor({
    required bool primary,
    required String hex,
  }) async {
    setState(() {
      if (primary) {
        _primaryHex = hex;
      } else {
        _backgroundHex = hex;
      }
    });
    await _persist(
      (r) => primary ? r.setPrimaryColorHex(hex) : r.setBackgroundColorHex(hex),
    );
  }

  Future<void> _setBrightness(AppBrightness brightness) async {
    setState(() => _brightness = brightness);
    await _persist((r) => r.setBrightness(brightness.name));
  }

  Future<void> _setLocale(String localeCode) async {
    setState(() => _localeCode = localeCode);
    await _persist((r) => r.setLocaleCode(localeCode));
  }

  Future<void> _setPowerSaving(PowerSavingMode mode) async {
    setState(() => _powerSavingMode = mode);
    await _persist((r) => r.setPowerSavingMode(mode));
  }

  Future<void> _setReduceAnimations(bool value) async {
    setState(() => _reduceAnimations = value);
    await _persist((r) => r.setReduceAnimations(value));
  }

  Future<void> _setHaptics(bool value) async {
    setState(() => _haptics = value);
    await _persist((r) => r.setHaptics(value));
  }

  Future<void> _setBiometricLock(bool value) async {
    if (!value) {
      setState(() => _biometricLock = false);
      await _persist((r) => r.setBiometricLock(false));
      return;
    }
    // Verify the system prompt works before enabling, otherwise the user
    // gets stuck on a dead lock screen.
    try {
      final ok = await AppLock.authenticate();
      if (!mounted) return;
      if (!ok) return;
      setState(() => _biometricLock = true);
      await _persist((r) => r.setBiometricLock(true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppLock.describeError(e))));
    }
  }

  Future<void> _setSyncInterval(int minutes) async {
    setState(() => _syncIntervalMin = minutes);
    await _persist((r) => r.setSyncIntervalMin(minutes));
    await ref.read(googleAutoSyncServiceProvider).reschedule();
  }

  Future<void> _setBackendSyncInterval(int minutes) async {
    setState(() => _backendSyncIntervalMin = minutes);
    await _persist((r) => r.setBackendSyncIntervalMin(minutes));
    await ref.read(backendAutoSyncServiceProvider).reschedule();
  }

  Future<void> _openNavOrder() async {
    final repo = _repo;
    if (repo == null) return;
    await showNavOrderSheet(
      context,
      repo,
      onSaved: () => ref.invalidate(settingsRepositoryProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_failed || _repo == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load settings.'),
              const SizedBox(height: 8),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SettingsSectionHeader(
            title: 'Appearance',
            description: 'Theme, colors and language.',
          ),
          BrightnessSelector(
            title: 'Brightness',
            help: 'Light, dark, or true-black AMOLED.',
            value: _brightness,
            onChanged: _setBrightness,
          ),
          ColorPresetPicker(
            title: 'Primary color',
            help: 'Accent for buttons, links and highlights.',
            presets: primaryPresets,
            selectedHex: _primaryHex,
            keyPrefix: 'primary',
            onSelected: (hex) => _selectColor(primary: true, hex: hex),
          ),
          HexColorFieldTile(
            title: 'Custom primary hex',
            help: 'Enter a valid value and press Enter.',
            value: _primaryHex,
            fieldKey: const ValueKey('primary-hex-field'),
            onSubmitted: (hex) => _selectColor(primary: true, hex: hex),
          ),
          ColorPresetPicker(
            title: 'Background color',
            help: 'Page background. Dark options pair with dark themes.',
            presets: backgroundPresets,
            selectedHex: _backgroundHex,
            keyPrefix: 'background',
            onSelected: (hex) => _selectColor(primary: false, hex: hex),
          ),
          HexColorFieldTile(
            title: 'Custom background hex',
            help: 'Enter a valid value and press Enter.',
            value: _backgroundHex,
            fieldKey: const ValueKey('background-hex-field'),
            onSubmitted: (hex) => _selectColor(primary: false, hex: hex),
          ),
          SettingsPickerTile<String>(
            title: l10n.languageTitle,
            help: 'System follows the device language.',
            value: _localeCode,
            items: [
              DropdownMenuItem(
                value: 'system',
                child: Text(l10n.languageSystem),
              ),
              DropdownMenuItem(value: 'en', child: Text(l10n.languageEnglish)),
              DropdownMenuItem(
                value: 'pt',
                child: Text(l10n.languagePortuguese),
              ),
            ],
            onChanged: _setLocale,
          ),
          const SettingsSectionHeader(
            title: 'Behavior and accessibility',
            description: 'Power use, motion and touch feedback.',
          ),
          SettingsPickerTile<PowerSavingMode>(
            title: 'Power saving mode',
            help: 'Auto reduces work when the battery is low.',
            value: _powerSavingMode,
            items: const [
              DropdownMenuItem(
                value: PowerSavingMode.auto,
                child: Text('Auto'),
              ),
              DropdownMenuItem(value: PowerSavingMode.on, child: Text('On')),
              DropdownMenuItem(value: PowerSavingMode.off, child: Text('Off')),
            ],
            onChanged: _setPowerSaving,
          ),
          SwitchListTile(
            title: const Text('Reduce animations'),
            subtitle: const Text('Fewer transitions and motion effects.'),
            value: _reduceAnimations,
            onChanged: _setReduceAnimations,
          ),
          SwitchListTile(
            title: const Text('Haptics'),
            subtitle: const Text('Vibration feedback on supported devices.'),
            value: _haptics,
            onChanged: _setHaptics,
          ),
          const SettingsSectionHeader(
            title: 'Accounts and sync',
            description: 'Sign in and control automatic sync.',
          ),
          ListTile(
            title: const Text('Account and sync'),
            subtitle: const Text('Sign in to sync your custom data.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const AuthScreen())),
          ),
          SettingsPickerTile<int>(
            title: 'Google auto-sync interval',
            help:
                'Sync starts right after sign-in. Tapping the Calendar, '
                'Tasks or Matrix title syncs now and restarts the countdown.',
            value: _syncIntervalMin,
            items: const [
              DropdownMenuItem(value: 0, child: Text('Off')),
              DropdownMenuItem(value: 15, child: Text('15 min')),
              DropdownMenuItem(value: 30, child: Text('30 min')),
              DropdownMenuItem(value: 60, child: Text('1 hour')),
              DropdownMenuItem(value: 120, child: Text('2 hours')),
            ],
            onChanged: _setSyncInterval,
          ),
          SettingsPickerTile<int>(
            title: 'Habits/focus auto-sync',
            help:
                'Periodic sync of habits and focus sessions. Manual when Off.',
            value: _backendSyncIntervalMin,
            items: const [
              DropdownMenuItem(value: 0, child: Text('Manual')),
              DropdownMenuItem(value: 15, child: Text('15 min')),
              DropdownMenuItem(value: 30, child: Text('30 min')),
              DropdownMenuItem(value: 60, child: Text('1 hour')),
              DropdownMenuItem(value: 120, child: Text('2 hours')),
            ],
            onChanged: _setBackendSyncInterval,
          ),
          const SettingsSectionHeader(
            title: 'Security',
            description: 'Protect the app when it opens.',
          ),
          SwitchListTile(
            title: const Text('Biometric app lock'),
            subtitle: Text(
              _biometricSupported
                  ? 'Require unlock on startup. Unsupported devices skip the lock.'
                  : 'Not available on this device.',
            ),
            value: _biometricSupported && _biometricLock,
            onChanged: _biometricSupported ? _setBiometricLock : null,
          ),
          const SettingsSectionHeader(
            title: 'Data and widgets',
            description: 'Backups and home-screen widgets.',
          ),
          const BackupSection(),
          ListTile(
            title: const Text('Manage home-screen widgets'),
            subtitle: const Text('Pin and configure launcher widgets.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const HomeWidgetsScreen(),
              ),
            ),
          ),
          const SettingsSectionHeader(
            title: 'Navigation',
            description: 'Choose how main sections are ordered.',
          ),
          ListTile(
            title: const Text('Reorder sections'),
            subtitle: const Text(
              'Change the order of Calendar, Tasks and other main sections.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openNavOrder,
          ),
        ],
      ),
    );
  }
}
