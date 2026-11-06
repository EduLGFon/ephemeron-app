part of '../tasks_screen.dart';

class _SmartListChip extends ConsumerWidget {
  const _SmartListChip({
    required this.smartList,
    required this.selected,
    required this.onSelected,
    required this.onLongPress,
  });

  final SmartList smartList;
  final bool selected;
  final VoidCallback onSelected;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(smartListTasksProvider(smartList));
    final count = results.maybeWhen(
      data: (tasks) => tasks.length,
      orElse: () => null,
    );
    return GestureDetector(
      onLongPress: onLongPress,
      child: ChoiceChip(
        avatar: const Icon(Icons.filter_alt_outlined, size: 16),
        label: Text(
          count == null ? smartList.name : '${smartList.name} ($count)',
        ),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}
