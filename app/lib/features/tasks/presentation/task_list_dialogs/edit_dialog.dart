part of '../task_list_dialogs.dart';

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
