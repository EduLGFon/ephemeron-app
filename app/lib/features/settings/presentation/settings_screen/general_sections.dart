part of '../settings_screen.dart';

List<Widget> _behaviorSection(_SettingsScreenState state) {
  return [
    const SettingsSectionHeader(
      title: 'Behavior and accessibility',
      description: 'Power use, motion and touch feedback.',
    ),
    SettingsPickerTile<PowerSavingMode>(
      title: 'Power saving mode',
      help: 'Auto reduces work when the battery is low.',
      value: state._powerSavingMode,
      items: const [
        DropdownMenuItem(value: PowerSavingMode.auto, child: Text('Auto')),
        DropdownMenuItem(value: PowerSavingMode.on, child: Text('On')),
        DropdownMenuItem(value: PowerSavingMode.off, child: Text('Off')),
      ],
      onChanged: state._setPowerSaving,
    ),
    SwitchListTile(
      title: const Text('Reduce animations'),
      subtitle: const Text('Fewer transitions and motion effects.'),
      value: state._reduceAnimations,
      onChanged: state._setReduceAnimations,
    ),
    SwitchListTile(
      title: const Text('Haptics'),
      subtitle: const Text('Vibration feedback on supported devices.'),
      value: state._haptics,
      onChanged: state._setHaptics,
    ),
  ];
}

List<Widget> _notificationsSection(_SettingsScreenState state) {
  return [
    const SettingsSectionHeader(
      title: 'Notifications',
      description: 'Task and reminder notifications.',
    ),
    SwitchListTile(
      title: const Text('Due tomorrow reminder'),
      subtitle: const Text(
        'Fires 24h before the due time, clamped to 09:00-17:00. '
        'Can be disabled.',
      ),
      value: state._taskDueTomorrowReminder,
      onChanged: state._setTaskDueTomorrowReminder,
    ),
  ];
}

List<Widget> _accountsSection(_SettingsScreenState state) {
  return [
    const SettingsSectionHeader(
      title: 'Accounts and sync',
      description: 'Sign in and control automatic sync.',
    ),
    ListTile(
      title: const Text('Account and sync'),
      subtitle: const Text('Sign in to sync your custom data.'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(
        state.context,
      ).push(MaterialPageRoute<void>(builder: (_) => const AuthScreen())),
    ),
    SettingsPickerTile<int>(
      title: 'Google auto-sync interval',
      help:
          'Sync starts right after sign-in. Tapping the Calendar, '
          'Tasks or Matrix title syncs now and restarts the countdown.',
      value: state._syncIntervalMin,
      items: const [
        DropdownMenuItem(value: 0, child: Text('Off')),
        DropdownMenuItem(value: 15, child: Text('15 min')),
        DropdownMenuItem(value: 30, child: Text('30 min')),
        DropdownMenuItem(value: 60, child: Text('1 hour')),
        DropdownMenuItem(value: 120, child: Text('2 hours')),
      ],
      onChanged: state._setSyncInterval,
    ),
    SettingsPickerTile<int>(
      title: 'Habits/focus auto-sync',
      help: 'Periodic sync of habits and focus sessions. Manual when Off.',
      value: state._backendSyncIntervalMin,
      items: const [
        DropdownMenuItem(value: 0, child: Text('Manual')),
        DropdownMenuItem(value: 15, child: Text('15 min')),
        DropdownMenuItem(value: 30, child: Text('30 min')),
        DropdownMenuItem(value: 60, child: Text('1 hour')),
        DropdownMenuItem(value: 120, child: Text('2 hours')),
      ],
      onChanged: state._setBackendSyncInterval,
    ),
  ];
}

List<Widget> _securitySection(_SettingsScreenState state) {
  return [
    const SettingsSectionHeader(
      title: 'Security',
      description: 'Protect the app when it opens.',
    ),
    SwitchListTile(
      title: const Text('Biometric app lock'),
      subtitle: Text(
        state._biometricSupported
            ? 'Require unlock on startup. Unsupported devices skip the lock.'
            : 'Not available on this device.',
      ),
      value: state._biometricSupported && state._biometricLock,
      onChanged: state._biometricSupported ? state._setBiometricLock : null,
    ),
  ];
}

List<Widget> _dataSection(_SettingsScreenState state, BuildContext context) {
  return [
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
        MaterialPageRoute<void>(builder: (_) => const HomeWidgetsScreen()),
      ),
    ),
  ];
}

List<Widget> _navigationSection(_SettingsScreenState state) {
  return [
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
      onTap: state._openNavOrder,
    ),
  ];
}
