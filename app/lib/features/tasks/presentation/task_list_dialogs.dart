// Dialogs and sheets for task-list management: create, rename/recolor and
// delete with an explicit task-move or task-delete choice.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_tokens.dart';
import '../../../data/drift/app_database.dart';
import '../../../domain/sources/source_label.dart';
import '../../../domain/sources/source_move.dart';
import '../application/tasks_providers.dart';

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
  final isLocal = list.remoteId == null;
  return sourceLabel(name: null, account: list.googleAccount, isLocal: isLocal);
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

class _ListInput {
  const _ListInput(this.name, this.color);

  final String name;
  final String color;
}

Future<void> showCreateTaskListDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final controller = TextEditingController();
  var selected = taskListPalette.first;
  final result = await showDialog<_ListInput>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('New list'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 16),
              const Text('Color'),
              const SizedBox(height: 8),
              _ColorPalette(
                selected: selected,
                onSelected: (color) => setState(() => selected = color),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.of(ctx).pop(_ListInput(name, colorToHex(selected)));
            },
            child: const Text('Create'),
          ),
        ],
      ),
    ),
  );
  if (result == null) return;
  await ref
      .read(taskRepositoryProvider)
      .createList(result.name, color: result.color);
}

/// Rename and recolor share one sheet; color is local-only for Google lists.
Future<void> showEditTaskListSheet(
  BuildContext context,
  WidgetRef ref,
  TaskList list,
) async {
  final controller = TextEditingController(text: list.name);
  var selected = taskListColor(list);
  final changed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Edit list'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 16),
              const Text('Color'),
              const SizedBox(height: 8),
              _ColorPalette(
                selected: selected,
                onSelected: (color) => setState(() => selected = color),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  final name = controller.text.trim();
  if (changed == true && name.isNotEmpty) {
    await ref
        .read(taskRepositoryProvider)
        .updateList(list.id, name: name, color: colorToHex(selected));
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

/// Deletion confirmation. Defaults to moving tasks when another list exists;
/// with no other list the only safe action is deleting the tasks too.
Future<void> showDeleteTaskListDialog(
  BuildContext context,
  WidgetRef ref,
  TaskList list,
) async {
  final others = [
    for (final other in ref.read(taskListsProvider).value ?? const <TaskList>[])
      if (other.id != list.id) other,
  ];
  var deleteTasks = others.isEmpty;
  var target = others.isEmpty ? null : others.first.id;
  final decision = await showDialog<_DeleteDecision>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Delete "${list.name}"?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (others.isNotEmpty) ...[
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Move tasks'),
                      icon: Icon(Icons.drive_file_move_outlined),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Delete tasks'),
                      icon: Icon(Icons.delete_outline),
                    ),
                  ],
                  selected: {deleteTasks},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      setState(() => deleteTasks = selection.single),
                ),
                const SizedBox(height: 12),
                if (!deleteTasks)
                  DropdownButtonFormField<String>(
                    initialValue: target,
                    decoration: const InputDecoration(
                      labelText: 'Move tasks to',
                    ),
                    items: [
                      for (final other in others)
                        DropdownMenuItem(
                          value: other.id,
                          child: Text(other.name),
                        ),
                    ],
                    onChanged: (value) => setState(() => target = value),
                  ),
              ],
              const SizedBox(height: 12),
              Text(
                deleteTasks
                    ? 'The list is removed. Its tasks go to Trash and stay '
                          'there until you restore or permanently delete them.'
                    : 'Tasks keep their details and move to the selected '
                          'list. The empty list is removed.',
              ),
              if (list.remoteId != null) ...[
                const SizedBox(height: 8),
                Text(
                  'The Google Tasks list is removed on the next sync.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(
              ctx,
            ).pop(_DeleteDecision(deleteTasks: deleteTasks, moveTo: target)),
            child: const Text('Delete list'),
          ),
        ],
      ),
    ),
  );
  if (decision == null) return;
  try {
    await ref
        .read(taskRepositoryProvider)
        .deleteList(
          list.id,
          deleteTasks: decision.deleteTasks,
          moveTasksToListId: decision.moveTo,
        );
  } on SourceMoveException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _DeleteDecision {
  const _DeleteDecision({required this.deleteTasks, required this.moveTo});

  final bool deleteTasks;
  final String? moveTo;
}
