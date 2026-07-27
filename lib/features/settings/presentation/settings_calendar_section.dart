import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/app_settings_provider.dart';
import 'settings_screen.dart'; // For static methods

class SettingsCalendarSection extends ConsumerWidget {
  const SettingsCalendarSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Calendar',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        ListTile(
          title: const Text('First day of the week'),
          subtitle: Text(SettingsScreen.dayName(settings.calendarStartDay)),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () {
            SettingsScreen.showStartDayPicker(context, ref, settings.calendarStartDay);
          },
        ),
        if (!kIsWeb)
          ListTile(
            title: const Text('Device Calendars'),
            subtitle: const Text('Toggle display of local phone calendars'),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () {
              SettingsScreen.showDeviceCalendarsSheet(context, ref);
            },
          ),
      ],
    );
  }
}
