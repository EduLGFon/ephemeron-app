// Quick-add bottom sheet: one field with shorthand and NLP parsing,
// live preview chips, save and save-and-add-another.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/parsing/quick_add_parser.dart';
import '../application/tasks_providers.dart';

Future<void> showQuickAdd(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _QuickAddSheet(),
  );
}

class _QuickAddSheet extends ConsumerStatefulWidget {
  const _QuickAddSheet();

  @override
  ConsumerState<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<_QuickAddSheet> {
  final _controller = TextEditingController();
  QuickAddParsed? _parsed;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() {
      _parsed = v.trim().isEmpty ? null : parseQuickAdd(v);
    });
  }

  Future<void> _save({required bool another}) async {
    final p = _parsed;
    if (p == null || p.title.isEmpty) return;
    final repo = ref.read(taskRepositoryProvider);
    String? listId;
    if (p.list != null) {
      final lists = await ref.read(taskListsProvider.future);
      listId = lists
          .where((l) => l.name.toLowerCase() == p.list!.toLowerCase())
          .map((l) => l.id)
          .firstOrNull;
      if (listId == null) listId = await repo.createList(p.list!);
    }
    await repo.createTask(
      title: p.title,
      listId: listId,
      priority: p.priority,
      dueDate: p.due == null
          ? null
          : '${p.due!.year.toString().padLeft(4, '0')}-'
                '${p.due!.month.toString().padLeft(2, '0')}-'
                '${p.due!.day.toString().padLeft(2, '0')}',
      dueTime: p.due == null || (p.due!.hour == 0 && p.due!.minute == 0)
          ? null
          : p.due!.hour * 60 + p.due!.minute,
      rrule: p.rrule,
      tags: p.tags,
    );
    if (!mounted) return;
    if (another) {
      _controller.clear();
      setState(() => _parsed = null);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _parsed;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Buy milk #groceries ~home -p1 tomorrow 9h',
                border: OutlineInputBorder(),
              ),
              onChanged: _onChanged,
              onSubmitted: (_) => _save(another: false),
            ),
            if (p != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  Chip(label: Text(p.title)),
                  for (final t in p.tags) Chip(label: Text('#$t')),
                  if (p.list != null) Chip(label: Text('~${p.list}')),
                  if (p.priority > 0) Chip(label: Text('P${5 - p.priority}')),
                  if (p.due != null)
                    Chip(label: Text(p.due.toString().substring(0, 16))),
                  if (p.rrule != null) Chip(label: Text(p.rrule!)),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: p == null ? null : () => _save(another: false),
                    child: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: p == null ? null : () => _save(another: true),
                  child: const Text('Save + another'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
