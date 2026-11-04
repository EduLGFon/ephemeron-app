// Bottom sheet used by Settings to reorder the main app sections.
import 'package:flutter/material.dart';

import '../../../core/ui/app_sheet.dart';
import '../../../core/ui/escape_to_close.dart';
import '../data/settings_repository.dart';

Future<void> showNavOrderSheet(
  BuildContext context,
  SettingsRepository repo, {
  required VoidCallback onSaved,
}) async {
  final current = List<int>.from(repo.navOrder);
  await showAppSheet<void>(
    context,
    builder: (ctx) => EscapeToClose(
      child: StatefulBuilder(
        builder: (ctx, setSt) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: ReorderableListView(
                    shrinkWrap: true,
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
                          title: Text(_sectionLabel(idx)),
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
                      onSaved();
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
    ),
  );
}

// Section ids are persisted as indexes; labels stay here until the app
// section enum exposes a shared label helper.
String _sectionLabel(int idx) {
  const names = [
    'Calendar',
    'Tasks',
    'Matrix',
    'Habits',
    'Countdowns',
    'Focus',
    'Notes',
  ];
  if (idx < 0 || idx >= names.length) return 'Section $idx';
  return names[idx];
}
