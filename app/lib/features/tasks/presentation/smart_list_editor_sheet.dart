// Smart-list editor: name plus the supported filter fields. Saving creates or
// updates a local SmartLists row; filterJson stays forward/backward tolerant.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/device_date_format.dart';
import '../../../core/time/picker_memory.dart';
import '../../../core/time/time.dart';
import '../../../core/ui/app_sheet.dart';
import '../../../core/ui/escape_to_close.dart';
import '../../../core/ui/sheet_padding.dart';
import '../../../data/drift/app_database.dart';
import '../../../domain/tasks/smart_filter.dart';
import '../../settings/application/settings_providers.dart';
import '../../settings/data/settings_repository.dart';
import '../application/tasks_providers.dart';

Future<void> showSmartListEditor(BuildContext context, {SmartList? smartList}) {
  return showAppSheet<void>(
    context,
    builder: (_) =>
        EscapeToClose(child: _SmartListEditor(smartList: smartList)),
  );
}

class _SmartListEditor extends ConsumerStatefulWidget {
  const _SmartListEditor({this.smartList});

  final SmartList? smartList;

  @override
  ConsumerState<_SmartListEditor> createState() => _SmartListEditorState();
}

class _SmartListEditorState extends ConsumerState<_SmartListEditor> {
  late final TextEditingController _name;
  late final TextEditingController _query;
  late bool _showCompleted;
  late SmartDueWindow _dueWindow;
  late String? _dueFrom;
  late String? _dueTo;
  late Set<int> _priorities;
  late Set<String> _listIds;
  late Set<String> _tagIds;
  late SmartSort _sort;

  @override
  void initState() {
    super.initState();
    final filter = SmartFilter.fromJson(widget.smartList?.filterJson);
    _name = TextEditingController(text: widget.smartList?.name ?? '');
    _query = TextEditingController(text: filter.query);
    _showCompleted = filter.showCompleted;
    _dueWindow = filter.dueWindow;
    _dueFrom = filter.dueFrom;
    _dueTo = filter.dueTo;
    _priorities = {...filter.priorities};
    _listIds = {...filter.listIds};
    _tagIds = {...filter.tagIds};
    _sort = filter.sort;
  }

  @override
  Widget build(BuildContext context) {
    final lists = ref.watch(taskListsProvider).value ?? const <TaskList>[];
    final tags = ref.watch(tagsProvider).value ?? const <Tag>[];
    final editing = widget.smartList != null;
    return SingleChildScrollView(
      padding: sheetPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            editing ? 'Edit smart list' : 'New smart list',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            autofocus: !editing,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Include completed'),
            value: _showCompleted,
            onChanged: (value) => setState(() => _showCompleted = value),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<SmartDueWindow>(
            initialValue: _dueWindow,
            decoration: const InputDecoration(
              labelText: 'Due date',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final window in SmartDueWindow.values)
                DropdownMenuItem(value: window, child: Text(window.label)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _dueWindow = value);
            },
          ),
          if (_dueWindow == SmartDueWindow.custom) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(from: true),
                    child: Text(_dueFrom ?? 'From date'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(from: false),
                    child: Text(_dueTo ?? 'To date'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text('Priority', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (var priority = 4; priority >= 1; priority--)
                FilterChip(
                  label: Text('P${5 - priority}'),
                  selected: _priorities.contains(priority),
                  onSelected: (selected) => setState(() {
                    selected
                        ? _priorities.add(priority)
                        : _priorities.remove(priority);
                  }),
                ),
            ],
          ),
          if (lists.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Lists', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final list in lists)
                  FilterChip(
                    label: Text(list.name),
                    selected: _listIds.contains(list.id),
                    onSelected: (selected) => setState(() {
                      selected
                          ? _listIds.add(list.id)
                          : _listIds.remove(list.id);
                    }),
                  ),
              ],
            ),
          ],
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Tags', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in tags)
                  FilterChip(
                    label: Text('#${tag.name}'),
                    selected: _tagIds.contains(tag.id),
                    onSelected: (selected) => setState(() {
                      selected ? _tagIds.add(tag.id) : _tagIds.remove(tag.id);
                    }),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _query,
            decoration: const InputDecoration(
              labelText: 'Text contains',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<SmartSort>(
            initialValue: _sort,
            decoration: const InputDecoration(
              labelText: 'Sort by',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final sort in SmartSort.values)
                DropdownMenuItem(value: sort, child: Text(sort.label)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _sort = value);
            },
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _save,
            child: Text(editing ? 'Save changes' : 'Create smart list'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate({required bool from}) async {
    final key = from
        ? PickerMemoryKeys.smartListDueFrom
        : PickerMemoryKeys.smartListDueTo;
    final current = from ? _dueFrom : _dueTo;
    SettingsRepository? settings;
    try {
      settings = await ref.read(settingsRepositoryProvider.future);
    } catch (_) {}
    if (!mounted) return;
    final initial = resolvePickerDate(
      current: current,
      remembered: settings?.getPickerDate(key),
      fallback: DateTime.now(),
    );
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    final value = dateKey(picked);
    try {
      await settings?.setPickerDate(key, value);
    } catch (_) {}
    setState(() {
      if (from) {
        _dueFrom = value;
      } else {
        _dueTo = value;
      }
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final filter = SmartFilter(
      listIds: _listIds.toList(),
      tagIds: _tagIds.toList(),
      priorities: _priorities,
      dueWindow: _dueWindow,
      dueFrom: _dueFrom,
      dueTo: _dueTo,
      showCompleted: _showCompleted,
      query: _query.text.trim(),
      sort: _sort,
    );
    final repo = ref.read(taskRepositoryProvider);
    final existing = widget.smartList;
    if (existing == null) {
      await repo.createSmartList(name, filter.toMap());
    } else {
      await repo.updateSmartList(
        existing.id,
        name: name,
        filter: filter.toMap(),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }
}

/// Short human summary used by the smart-list manager rows.
String smartFilterSummary(SmartList smartList) {
  final filter = SmartFilter.fromJson(smartList.filterJson);
  final parts = <String>[filter.dueWindow.label, filter.sort.label];
  if (filter.showCompleted) parts.add('completed included');
  return parts.join(' - ');
}

/// Exposed for date labels in the manager without importing intl there.
String smartListDateLabel(BuildContext context, String? key) {
  if (key == null) return 'Any date';
  final date = DateTime.tryParse(key);
  return date == null ? key : DeviceDateFormat.yMMMd(context).format(date);
}
