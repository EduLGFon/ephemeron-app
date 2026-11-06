part of '../settings_screen.dart';

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
  bool _taskDueTomorrowReminder = true;
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
        _taskDueTomorrowReminder = repo.taskDueTomorrowReminder;
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

  Future<void> _setTaskDueTomorrowReminder(bool value) async {
    setState(() => _taskDueTomorrowReminder = value);
    await _persist((r) => r.setTaskDueTomorrowReminder(value));
    try {
      await ref
          .read(alarmRepositoryProvider)
          .rebuildWindow(dueTomorrowEnabled: value);
    } catch (_) {
      // Best-effort reschedule; failures are non-fatal.
    }
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
          ..._appearanceSection(this, l10n),
          ..._behaviorSection(this),
          ..._notificationsSection(this),
          ..._accountsSection(this),
          ..._securitySection(this),
          ..._dataSection(this, context),
          ..._navigationSection(this),
        ],
      ),
    );
  }
}
