import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/app_settings_provider.dart';
import 'settings_screen.dart';

class SettingsNotificationsSection extends ConsumerWidget {
  const SettingsNotificationsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Alarm Configuration',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        ListTile(
          title: const Text('Short Alarm Sound Path'),
          subtitle: Text(settings.alarmShortSoundPath),
          trailing: const Icon(Icons.music_note, size: 20),
          onTap: () => SettingsScreen.editSoundPath(
              context, ref, 'short', settings.alarmShortSoundPath),
        ),
        ListTile(
          title: const Text('Long Alarm Sound Path'),
          subtitle: Text(settings.alarmLongSoundPath),
          trailing: const Icon(Icons.music_note, size: 20),
          onTap: () => SettingsScreen.editSoundPath(
              context, ref, 'long', settings.alarmLongSoundPath),
        ),
        ListTile(
          title: const Text('Alarm Screen Background'),
          subtitle: Row(
            children: [
              Container(
                width: 24,
                height: 16,
                decoration: BoxDecoration(
                  color: SettingsScreen.parseColor(settings.alarmBackground),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Text(settings.alarmBackground),
            ],
          ),
          trailing: const Icon(Icons.color_lens, size: 20),
          onTap: () => SettingsScreen.editAlarmBackground(
              context, ref, settings.alarmBackground),
        ),
      ],
    );
  }
}
