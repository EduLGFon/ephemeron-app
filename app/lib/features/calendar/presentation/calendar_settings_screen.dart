// Calendar settings: calendars (add/enable/default), week start,
// default duration.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/application/settings_providers.dart';
import '../application/calendar_providers.dart';

class CalendarSettingsScreen extends ConsumerWidget {
  const CalendarSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calsAsync = ref.watch(calendarsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Calendars')),
      body: ListView(
        children: [
          calsAsync.maybeWhen(
            data: (cals) => Column(
              children: [
                for (final c in cals)
                  SwitchListTile(
                    value: c.enabled,
                    onChanged: (v) => ref
                        .read(eventRepositoryProvider)
                        .setCalendarEnabled(c.id, v),
                    title: Text(c.name),
                    subtitle: Text(c.source),
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Add local calendar'),
                  onTap: () => _addCalendar(context, ref),
                ),
              ],
            ),
            orElse: () => const ListTile(title: Text('Loading…')),
          ),
          const Divider(),
          ListTile(
            title: const Text('Week starts on'),
            trailing: FutureBuilder<int>(
              future: _weekStart(ref),
              builder: (ctx, snap) => DropdownButton<int>(
                value: snap.data ?? DateTime.monday,
                items: const [
                  DropdownMenuItem(
                    value: DateTime.monday,
                    child: Text('Monday'),
                  ),
                  DropdownMenuItem(
                    value: DateTime.sunday,
                    child: Text('Sunday'),
                  ),
                  DropdownMenuItem(
                    value: DateTime.saturday,
                    child: Text('Saturday'),
                  ),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  final repo = await ref.read(
                    settingsRepositoryProvider.future,
                  );
                  await repo.setWeekStart(v);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Week start saved')),
                    );
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<int> _weekStart(WidgetRef ref) async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    return repo.weekStart;
  }

  Future<void> _addCalendar(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New calendar'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await ref.read(eventRepositoryProvider).createCalendar(name);
    }
  }
}
