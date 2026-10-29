import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_screen.dart';
import '../application/settings_providers.dart';
import '../data/settings_repository.dart';
import '../../../core/theme/theme_tokens.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRepo = ref.watch(settingsRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: asyncRepo.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (repo) => ListView(
          children: [
            const _SectionHeader('Appearance'),
            ListTile(
              title: const Text('Primary color'),
              subtitle: Wrap(
                spacing: 8,
                children: [
                  for (final c in primaryPresets)
                    GestureDetector(
                      onTap: () => repo.setPrimaryColorHex(_hex(c)),
                      child: CircleAvatar(backgroundColor: c, radius: 14),
                    ),
                ],
              ),
            ),
            ListTile(
              title: const Text('Background color'),
              subtitle: Wrap(
                spacing: 8,
                children: [
                  for (final c in backgroundPresets)
                    GestureDetector(
                      onTap: () => repo.setBackgroundColorHex(_hex(c)),
                      child: CircleAvatar(backgroundColor: c, radius: 14),
                    ),
                ],
              ),
            ),
            ListTile(
              title: const Text('Brightness'),
              trailing: DropdownButton<String>(
                value: repo.brightness,
                items: const [
                  DropdownMenuItem(value: 'light', child: Text('Light')),
                  DropdownMenuItem(value: 'dark', child: Text('Dark')),
                  DropdownMenuItem(value: 'amoled', child: Text('AMOLED')),
                ],
                onChanged: (v) {
                  if (v != null) repo.setBrightness(v);
                },
              ),
            ),
            ListTile(
              title: const Text('Custom primary hex'),
              trailing: SizedBox(
                width: 120,
                child: TextField(
                  decoration: const InputDecoration(hintText: '#RRGGBB'),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) {
                      repo.setPrimaryColorHex(v.trim());
                    }
                  },
                ),
              ),
            ),
            ListTile(
              title: const Text('Custom background hex'),
              trailing: SizedBox(
                width: 120,
                child: TextField(
                  decoration: const InputDecoration(hintText: '#RRGGBB'),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) {
                      repo.setBackgroundColorHex(v.trim());
                    }
                  },
                ),
              ),
            ),
            const _SectionHeader('Power and accessibility'),
            ListTile(
              title: const Text('Power saving mode'),
              trailing: DropdownButton<String>(
                value: repo.powerSavingMode.name,
                items: const [
                  DropdownMenuItem(value: 'auto', child: Text('Auto')),
                  DropdownMenuItem(value: 'on', child: Text('On')),
                  DropdownMenuItem(value: 'off', child: Text('Off')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    repo.setPowerSavingMode(
                      PowerSavingMode.values.firstWhere((e) => e.name == v),
                    );
                  }
                },
              ),
            ),
            SwitchListTile(
              title: const Text('Reduce animations'),
              value: repo.reduceAnimations,
              onChanged: repo.setReduceAnimations,
            ),
            SwitchListTile(
              title: const Text('Haptics'),
              value: repo.haptics,
              onChanged: repo.setHaptics,
            ),
            const _SectionHeader('Navigation'),
            ListTile(
              title: const Text('Reorder sections'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _reorder(context, ref, repo),
            ),
            ListTile(
              title: const Text('Account and sync'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AuthScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

  Future<void> _reorder(
    BuildContext context,
    WidgetRef ref,
    SettingsRepository repo,
  ) async {
    final current = List<int>.from(repo.navOrder);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(
              children: [
                Expanded(
                  child: ReorderableListView(
                    onReorderItem: (oldIndex, newIndex) {
                      setSt(() {
                        final item = current.removeAt(oldIndex);
                        current.insert(newIndex, item);
                      });
                    },
                    children: [
                      for (final idx in current)
                        ListTile(
                          key: ValueKey(idx),
                          title: Text(AppSectionLabel.label(idx)),
                          trailing: const Icon(Icons.drag_handle),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: () async {
                      await repo.setNavOrder(current);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

// Avoid importing app_sections enum naming mismatch.
class AppSectionLabel {
  static String label(int idx) {
    const names = [
      'Calendar',
      'Tasks',
      'Matrix',
      'Habits',
      'Countdowns',
      'Focus',
      'Notes',
    ];
    return names[idx];
  }
}
