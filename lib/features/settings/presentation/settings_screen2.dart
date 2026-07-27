import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_appearance_section.dart';
import 'settings_calendar_section.dart';
import 'settings_notifications_section.dart';
import 'settings_sync_section.dart';
import 'settings_about_section.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: const [
          SettingsAppearanceSection(),
          Divider(),
          SettingsCalendarSection(),
          Divider(),
          SettingsSyncSection(),
          Divider(),
          SettingsNotificationsSection(),
          Divider(),
          SettingsAboutSection(),
        ],
      ),
    );
  }
}
