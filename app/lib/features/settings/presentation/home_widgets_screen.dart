import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../../data/services/home_widget_service.dart';
import '../../../data/services/widget_config_store.dart';
import '../../countdowns/application/countdowns_providers.dart';
import '../../habits/application/habits_providers.dart';
import '../../notes/application/notes_providers.dart';
import '../../tasks/application/tasks_providers.dart';

class HomeWidgetsScreen extends ConsumerWidget {
  const HomeWidgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(widgetConfigStoreProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Home-screen widgets')),
      body: configAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load config: $e')),
        data: (store) => ListView(
          children: [
            const ListTile(
              title: Text('Pin a widget to your home screen.'),
              subtitle: Text(
                'Android only; availability depends on your launcher. '
                'Some widgets can be bound to a specific list, note, '
                'countdown, tag, or habit.',
              ),
            ),
            for (final w in homeWidgets)
              ListTile(
                title: Text(w.provider.replaceFirst('WidgetProvider', '')),
                subtitle: Text(_subtitle(store, w)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widgetConfigKinds.containsKey(w.provider))
                      TextButton(
                        onPressed: () =>
                            _configure(context, ref, store, w.provider),
                        child: const Text('Set up'),
                      ),
                    TextButton(
                      onPressed: () => _pin(context, w.provider),
                      child: const Text('Pin'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _subtitle(WidgetConfigStore store, HomeWidgetDefinition w) {
    final kind = widgetConfigKinds[w.provider];
    final current = store.get(w.provider);
    if (kind == null) return w.keyPrefix;
    if (current == null) return '${w.keyPrefix} (all)';
    return '${w.keyPrefix} ($kind: $current)';
  }

  Future<void> _pin(BuildContext context, String provider) async {
    try {
      await HomeWidget.requestPinWidget(
        androidName: provider,
        qualifiedAndroidName: 'com.spotnik.ephemeron.$provider',
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pinning not supported here.')),
        );
      }
    }
  }

  Future<void> _configure(
    BuildContext context,
    WidgetRef ref,
    WidgetConfigStore store,
    String provider,
  ) async {
    final kind = widgetConfigKinds[provider];
    if (kind == null) return;
    final options = await _optionsFor(ref, kind);
    if (!context.mounted) return;
    String? selected = store.get(provider);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Bind $provider'),
        content: options.isEmpty
            ? const Text('No options available yet.')
            : DropdownButton<String?>(
                value: options.any((o) => o.$1 == selected)
                    ? selected
                    : null,
                hint: const Text('All (default)'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All (default)'),
                  ),
                  for (final o in options)
                    DropdownMenuItem<String?>(
                      value: o.$1,
                      child: Text(o.$2),
                    ),
                ],
                onChanged: (v) {
                  selected = v;
                  Navigator.of(ctx).pop();
                },
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    await store.set(provider, selected);
    ref.invalidate(widgetConfigStoreProvider);
  }

  /// Returns (id, label) options for a config kind.
  Future<List<(String, String)>> _optionsFor(
    WidgetRef ref,
    String kind,
  ) async {
    try {
      switch (kind) {
        case 'listId':
          final lists = await ref.read(taskListsProvider.future);
          return [for (final l in lists) (l.id, l.name)];
        case 'tag':
          final tags = await ref.read(tagsProvider.future);
          return [for (final t in tags) (t.name, t.name)];
        case 'smartListId':
          final lists = await ref.read(smartListsProvider.future);
          return [for (final l in lists) (l.id, l.name)];
        case 'taskId':
          final tasks = await ref.read(openTasksProvider(null).future);
          return [
            for (final t in tasks.take(50)) (t.id, t.title),
          ];
        case 'noteId':
          final notes = await ref.read(folderNotesProvider(null).future);
          return [for (final n in notes.take(50)) (n.id, n.title)];
        case 'countdownId':
          final items = await ref.read(countdownsProvider.future);
          return [for (final c in items) (c.id, c.title)];
        case 'habitId':
          final habits = await ref.read(habitsProvider(false).future);
          return [for (final h in habits) (h.id, h.name)];
        default:
          return [];
      }
    } catch (_) {
      return [];
    }
  }
}
