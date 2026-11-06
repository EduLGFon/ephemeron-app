part of '../task_list_dialogs.dart';

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
