// Calendar settings: calendars (add/enable/default), week start,
// default duration.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/application/settings_providers.dart';
import '../application/calendar_providers.dart';
import '../../../data/drift/app_database.dart';
import '../../../data/services/device_calendar_import_service.dart';

List<MapEntry<String, List<Calendar>>> _groupCalendars(List<Calendar> cals) {
  final map = <String, List<Calendar>>{};
  for (final c in cals) {
    final key = c.source == 'google' ? 'Google' : 'Device';
    map.putIfAbsent(key, () => []).add(c);
  }
  return map.entries.toList();
}

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
                for (final group in _groupCalendars(cals)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      group.key,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  for (final c in group.value)
                    SwitchListTile(
                      value: c.enabled,
                      onChanged: (v) => ref
                          .read(eventRepositoryProvider)
                          .setCalendarEnabled(c.id, v),
                      title: Text(c.name),
                      subtitle: Text(c.source),
                    ),
                ],
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Add local calendar'),
                  onTap: () => _addCalendar(context, ref),
                ),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Import from device calendars'),
                  onTap: () => _importDeviceCalendars(context, ref),
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

  Future<void> _importDeviceCalendars(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final service = DeviceCalendarImportService(
      ref.read(eventRepositoryProvider),
    );
    if (!service.isSupported) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device calendars not supported here')),
        );
      }
      return;
    }
    final granted = await service.requestPermission();
    if (granted == 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Calendar permission denied')),
        );
      }
      return;
    }
    final deviceCals = await service.listCalendars();
    if (deviceCals.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No device calendars found')),
        );
      }
      return;
    }
    final appCals =
        (await ref.read(eventRepositoryProvider).watchCalendars().first)
            .where((c) => c.source == 'device')
            .toList();
    if (appCals.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Create a local calendar first')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    String targetId = appCals.first.id;
    final selected = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Import device calendars'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: targetId,
                    items: [
                      for (final c in appCals)
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() => targetId = v ?? targetId),
                    decoration: const InputDecoration(
                      labelText: 'Target calendar',
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final dc in deviceCals)
                    CheckboxListTile(
                      value: selected.contains(dc.id),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          selected.add(dc.id);
                        } else {
                          selected.remove(dc.id);
                        }
                      }),
                      title: Text(dc.name),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Import'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || selected.isEmpty) return;
    int total = 0;
    for (final id in selected) {
      total += await service.importCalendar(
        deviceCalendarId: id,
        targetCalendarId: targetId,
      );
    }
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Imported $total events')));
    }
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
