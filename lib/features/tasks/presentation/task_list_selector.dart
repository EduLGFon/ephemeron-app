import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_palettes.dart';
import '../../../data/local/database.dart';
import '../application/task_providers.dart';

class TaskListSelector extends ConsumerWidget {
  const TaskListSelector({
    super.key,
    required this.palette,
    required this.currentId,
    required this.currentListName,
    required this.lists,
    required this.customSmartLists,
    required this.tags,
  });

  final AppPalette palette;
  final String currentId;
  final String currentListName;
  final List<TaskList> lists;
  final List<CustomSmartList> customSmartLists;
  final List<Tag> tags;

  Color _parseColor(String hex) {
    try {
      final c = hex.replaceAll('#', '');
      return Color(int.parse('FF\$c', radix: 16));
    } catch (_) {
      return const Color(0xFF1B4B4A);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: palette.surface.withValues(alpha: 0.95),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          textStyle: TextStyle(color: palette.text),
        ),
      ),
      child: PopupMenuButton<String>(
        onSelected: (id) {
          if (id == '__new__') {
            _createList(context, ref, palette);
          } else if (id == '__new_smart__') {
            _createSmartList(context, ref, palette, tags);
          } else {
            ref.read(selectedListIdProvider.notifier).state = id;
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem<String>(
            enabled: false,
            child: Text('SMART LISTS',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
          ),
          _buildSmartMenuItem('smart:today', 'Today', Icons.today_rounded,
              palette, currentId),
          _buildSmartMenuItem('smart:tomorrow', 'Tomorrow',
              Icons.wb_sunny_rounded, palette, currentId),
          _buildSmartMenuItem('smart:next7Days', 'Next 7 Days',
              Icons.calendar_month_rounded, palette, currentId),
          _buildSmartMenuItem('smart:completed', 'Completed',
              Icons.check_circle_outline_rounded, palette, currentId),
          _buildSmartMenuItem('smart:trash', 'Trash',
              Icons.delete_outline_rounded, palette, currentId),
          _buildSmartMenuItem('smart:wontDo', "Won't Do",
              Icons.block_rounded, palette, currentId),
          if (customSmartLists.isNotEmpty) ...[
            const PopupMenuDivider(),
            const PopupMenuItem<String>(
              enabled: false,
              child: Text('CUSTOM SMART LISTS',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
            ),
            for (final item in customSmartLists) ...[
              (() {
                final val = 'custom_smart:\${item.id}';
                final isSelected = val == currentId;
                return PopupMenuItem<String>(
                  value: val,
                  child: Row(
                    children: [
                      Icon(Icons.filter_list_rounded,
                          color: isSelected
                              ? palette.primary
                              : _parseColor(item.colorHex),
                          size: 20),
                      const SizedBox(width: 8),
                      Text(
                        item.name,
                        style: TextStyle(
                          color: palette.text,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      if (isSelected) ...[
                        const Spacer(),
                        Icon(Icons.check, color: palette.primary, size: 16),
                      ],
                    ],
                  ),
                );
              }()),
            ],
          ],
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            enabled: false,
            child: Text('LISTS',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
          ),
          for (final list in lists) ...[
            (() {
              final isSelected = list.id == currentId;
              return PopupMenuItem<String>(
                value: list.id,
                child: Row(
                  children: [
                    Icon(
                      list.isInbox
                          ? Icons.inbox_rounded
                          : Icons.list_rounded,
                      color: isSelected
                          ? palette.primary
                          : (list.isInbox
                              ? palette.primary.withValues(alpha: 0.5)
                              : _parseColor(list.colorHex)),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      list.name,
                      style: TextStyle(
                        color: palette.text,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    if (isSelected) ...[
                      const Spacer(),
                      Icon(Icons.check, color: palette.primary, size: 16),
                    ],
                  ],
                ),
              );
            }()),
          ],
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: '__new__',
            child: Row(
              children: [
                Icon(Icons.add, color: palette.primary, size: 20),
                const SizedBox(width: 8),
                Text('New list...',
                    style: TextStyle(
                        color: palette.primary,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: '__new_smart__',
            child: Row(
              children: [
                Icon(Icons.filter_alt_outlined,
                    color: palette.primary, size: 20),
                const SizedBox(width: 8),
                Text('New smart list...',
                    style: TextStyle(
                        color: palette.primary,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              currentListName,
              style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 24),
            ),
            Icon(Icons.keyboard_arrow_down,
                color: palette.text.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildSmartMenuItem(String value, String name,
      IconData icon, AppPalette palette, String currentId) {
    final isSelected = value == currentId;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon,
              color: isSelected
                  ? palette.primary
                  : palette.text.withValues(alpha: 0.5),
              size: 20),
          const SizedBox(width: 8),
          Text(
            name,
            style: TextStyle(
              color: palette.text,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (isSelected) ...[
            const Spacer(),
            Icon(Icons.check, color: palette.primary, size: 16),
          ],
        ],
      ),
    );
  }

  Future<void> _createSmartList(
      BuildContext context, WidgetRef ref, AppPalette palette, List<Tag> tags) async {
    final nameController = TextEditingController();
    String? selectedDateFilter;
    int? selectedMinPriority;
    String? selectedTagId;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: palette.surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text('New Smart List',
                  style: TextStyle(
                      color: palette.text, fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      style: TextStyle(color: palette.text),
                      decoration: InputDecoration(
                        hintText: 'Smart list name',
                        hintStyle: TextStyle(
                            color: palette.text.withValues(alpha: 0.5)),
                        enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: palette.text.withValues(alpha: 0.2))),
                        focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: palette.primary)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Date Filter',
                        style: TextStyle(
                            color: palette.text.withValues(alpha: 0.7),
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                    DropdownButton<String?>(
                      value: selectedDateFilter,
                      dropdownColor: palette.surface,
                      style: TextStyle(color: palette.text),
                      isExpanded: true,
                      underline: Container(
                          height: 1,
                          color: palette.text.withValues(alpha: 0.2)),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Any Time')),
                        DropdownMenuItem(value: 'today', child: Text('Today')),
                        DropdownMenuItem(
                            value: 'tomorrow', child: Text('Tomorrow')),
                        DropdownMenuItem(
                            value: 'thisWeek', child: Text('This Week')),
                        DropdownMenuItem(
                            value: 'next7Days', child: Text('Next 7 Days')),
                      ],
                      onChanged: (val) =>
                          setDialogState(() => selectedDateFilter = val),
                    ),
                    const SizedBox(height: 16),
                    Text('Priority Filter',
                        style: TextStyle(
                            color: palette.text.withValues(alpha: 0.7),
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                    DropdownButton<int?>(
                      value: selectedMinPriority,
                      dropdownColor: palette.surface,
                      style: TextStyle(color: palette.text),
                      isExpanded: true,
                      underline: Container(
                          height: 1,
                          color: palette.text.withValues(alpha: 0.2)),
                      items: const [
                        DropdownMenuItem(
                            value: null, child: Text('Any Priority')),
                        DropdownMenuItem(value: 3, child: Text('High Only')),
                        DropdownMenuItem(
                            value: 2, child: Text('Medium & High')),
                      ],
                      onChanged: (val) =>
                          setDialogState(() => selectedMinPriority = val),
                    ),
                    const SizedBox(height: 16),
                    Text('Tag Filter',
                        style: TextStyle(
                            color: palette.text.withValues(alpha: 0.7),
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                    DropdownButton<String?>(
                      value: selectedTagId,
                      dropdownColor: palette.surface,
                      style: TextStyle(color: palette.text),
                      isExpanded: true,
                      underline: Container(
                          height: 1,
                          color: palette.text.withValues(alpha: 0.2)),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('Any Tag')),
                        for (final tag in tags)
                          DropdownMenuItem(
                              value: tag.id, child: const Text('#\${tag.name}')),
                      ],
                      onChanged: (val) =>
                          setDialogState(() => selectedTagId = val),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Cancel',
                      style: TextStyle(
                          color: palette.text.withValues(alpha: 0.6))),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.primary,
                    foregroundColor: palette.background,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    if (nameController.text.trim().isEmpty) return;
                    Navigator.pop(context, true);
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true &&
        nameController.text.trim().isNotEmpty &&
        context.mounted) {
      final name = nameController.text.trim();
      final smartList =
          await ref.read(taskRepositoryProvider).createCustomSmartList(
                name: name,
                dateFilter: selectedDateFilter,
                minPriority: selectedMinPriority,
                tagId: selectedTagId,
              );
      ref.read(selectedListIdProvider.notifier).state =
          'custom_smart:\${smartList.id}';
    }
  }

  Future<void> _createList(BuildContext context, WidgetRef ref, AppPalette palette) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('New list',
            style: TextStyle(color: palette.text, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: palette.text),
          decoration: InputDecoration(
            hintText: 'List name',
            hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.5)),
            enabledBorder: UnderlineInputBorder(
                borderSide:
                    BorderSide(color: palette.text.withValues(alpha: 0.2))),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: palette.primary)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: palette.text.withValues(alpha: 0.6))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: palette.primary,
              foregroundColor: palette.background,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    final list = await ref.read(taskRepositoryProvider).createList(name: name);
    ref.read(selectedListIdProvider.notifier).state = list.id;
  }
}
