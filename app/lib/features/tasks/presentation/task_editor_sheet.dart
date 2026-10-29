// Task create/edit sheet with list, priority, due chips, tags, subtasks.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/drift/app_database.dart';
import '../application/tasks_providers.dart';

Future<void> showTaskEditor(
  BuildContext context, {
  Task? task,
  String? parentId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TaskEditor(task: task, parentId: parentId),
  );
}

class _TaskEditor extends ConsumerStatefulWidget {
  const _TaskEditor({this.task, this.parentId});

  final Task? task;
  final String? parentId;

  @override
  ConsumerState<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends ConsumerState<_TaskEditor> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late final TextEditingController _tags;
  String? _listId;
  int _priority = 0;
  String? _dueDate;
  bool _pinned = false;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _title = TextEditingController(text: t?.title ?? '');
    _notes = TextEditingController(text: t?.notes ?? '');
    _tags = TextEditingController();
    _listId = t?.listId;
    _priority = t?.priority ?? 0;
    _dueDate = t?.dueDate;
    _pinned = t?.pinned ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _tags.dispose();
    super.dispose();
  }

  String _fmtDue(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final repo = ref.read(taskRepositoryProvider);
    final tagNames = _tags.text
        .split(RegExp(r'[,\s]+'))
        .map((s) => s.replaceAll('#', '').trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final existing = widget.task;
    if (existing == null) {
      await repo.createTask(
        title: title,
        listId: _listId,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        priority: _priority,
        dueDate: _dueDate,
        pinned: _pinned,
        parentId: widget.parentId,
        tags: tagNames,
      );
    } else {
      await repo.updateTask(
        existing.id,
        title: title,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        priority: _priority,
        dueDate: () => _dueDate,
        listId: _listId,
        pinned: _pinned,
      );
      if (tagNames.isNotEmpty) {
        await repo.setTaskTags(existing.id, tagNames);
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final listsAsync = ref.watch(taskListsProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                autofocus: widget.task == null,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              listsAsync.maybeWhen(
                data: (lists) => DropdownButtonFormField<String?>(
                  initialValue: _listId,
                  decoration: const InputDecoration(
                    labelText: 'List',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('No list')),
                    for (final l in lists)
                      DropdownMenuItem(value: l.id, child: Text(l.name)),
                  ],
                  onChanged: (v) => setState(() => _listId = v),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Priority'),
                  const SizedBox(width: 8),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('None')),
                      ButtonSegment(value: 1, label: Text('P4')),
                      ButtonSegment(value: 2, label: Text('P3')),
                      ButtonSegment(value: 3, label: Text('P2')),
                      ButtonSegment(value: 4, label: Text('P1')),
                    ],
                    selected: {_priority},
                    onSelectionChanged: (s) =>
                        setState(() => _priority = s.single),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _dueChip(context, 'Today', _fmtDue(DateTime.now())),
                  _dueChip(
                    context,
                    'Tomorrow',
                    _fmtDue(DateTime.now().add(const Duration(days: 1))),
                  ),
                  _dueChip(
                    context,
                    'Next Mon',
                    _fmtDue(_nextWeekday(DateTime.now(), DateTime.monday)),
                  ),
                  if (_dueDate != null)
                    ActionChip(
                      label: Text('Clear ($_dueDate)'),
                      onPressed: () => setState(() => _dueDate = null),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _tags,
                decoration: const InputDecoration(
                  labelText: 'Tags (space separated)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _pinned,
                onChanged: (v) => setState(() => _pinned = v),
                title: const Text('Pinned'),
                contentPadding: EdgeInsets.zero,
              ),
              if (widget.task != null) _SubtaskSection(task: widget.task!),
              FilledButton(
                onPressed: _save,
                child: Text(widget.task == null ? 'Create' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dueChip(BuildContext context, String label, String value) {
    final selected = _dueDate == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _dueDate = selected ? null : value),
    );
  }

  DateTime _nextWeekday(DateTime now, int weekday) {
    var d = DateTime(now.year, now.month, now.day + 1);
    while (d.weekday != weekday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }
}

class _SubtaskSection extends ConsumerWidget {
  const _SubtaskSection({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subsAsync = ref.watch(subtasksProvider(task.id));
    return subsAsync.maybeWhen(
      data: (subs) {
        final done = subs.where((s) => s.completedAt != null).length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Subtasks $done/${subs.length}'),
            for (final s in subs)
              CheckboxListTile(
                value: s.completedAt != null,
                onChanged: (_) {
                  final repo = ref.read(taskRepositoryProvider);
                  if (s.completedAt != null) {
                    repo.uncompleteTask(s.id);
                  } else {
                    repo.completeTask(s.id);
                  }
                },
                title: Text(s.title),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            TextButton.icon(
              onPressed: () => showTaskEditor(context, parentId: task.id),
              icon: const Icon(Icons.add),
              label: const Text('Add subtask'),
            ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
