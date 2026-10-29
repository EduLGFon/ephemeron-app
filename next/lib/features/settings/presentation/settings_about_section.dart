import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_screen.dart';

class SettingsAboutSection extends ConsumerWidget {
  const SettingsAboutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Developer Tools',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        ListTile(
          title: const Text('View developer logs'),
          subtitle: const Text(
              'Check sync and authentication events / error messages'),
          trailing: const Icon(Icons.bug_report, size: 20),
          onTap: () {
            SettingsScreen.showDevLogsDialog(context, ref);
          },
        ),
      ],
    );
  }
}
