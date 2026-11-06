// Dialogs and sheets for task-list management: create, rename/recolor and
// delete with an explicit task-move or task-delete choice.
//
// Split across `part` files under `task_list_dialogs/` (U10b); this file is
// the stable public entry point.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_tokens.dart';
import '../../../data/drift/app_database.dart';
import '../../../domain/sources/source_label.dart';
import '../../../domain/sources/source_move.dart';
import '../application/tasks_providers.dart';

part 'task_list_dialogs/create_dialog.dart';
part 'task_list_dialogs/edit_dialog.dart';
part 'task_list_dialogs/delete_dialog.dart';

const List<Color> taskListPalette = primaryPresets;

/// Stable display color for a list: stored hex when valid, otherwise a
/// deterministic preset so legacy/Google lists still differ visually.
Color taskListColor(TaskList list) {
  final raw = list.color;
  if (raw != null && isValidHex(raw)) return parseHex(raw);
  var hash = 0;
  for (final unit in list.id.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return taskListPalette[hash % taskListPalette.length];
}

String? taskListAccountLabel(TaskList list) {
  final isLocal =
      list.remoteId == null &&
      list.googleAccount == null &&
      list.microsoftAccount == null;
  return sourceLabel(
    name: null,
    account: accountForSource(
      googleAccount: list.googleAccount,
      microsoftAccount: list.microsoftAccount,
    ),
    isLocal: isLocal,
  );
}

class TaskListColorDot extends StatelessWidget {
  const TaskListColorDot({super.key, required this.list, this.size = 12});

  final TaskList list;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'List color',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: taskListColor(list),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _ColorPalette extends StatelessWidget {
  const _ColorPalette({required this.selected, required this.onSelected});

  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (index, color) in taskListPalette.indexed)
          Tooltip(
            message: 'Color ${index + 1}',
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onSelected(color),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color == selected
                        ? Theme.of(context).colorScheme.onSurface
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: color == selected
                    ? const Icon(Icons.check, size: 18, color: Colors.white)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}
