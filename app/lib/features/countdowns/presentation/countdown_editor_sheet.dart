// Countdown editor bottom sheet: create and edit.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/drift/app_database.dart';
import '../application/countdowns_providers.dart';

Future<void> showCountdownEditor(BuildContext context, {Countdown? countdown}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CountdownEditorSheet(countdown: countdown),
  );
}

class _CountdownEditorSheet extends ConsumerStatefulWidget {
  const _CountdownEditorSheet({this.countdown});

  final Countdown? countdown;

  @override
  ConsumerState<_CountdownEditorSheet> createState() =>
      _CountdownEditorSheetState();
}

class _CountdownEditorSheetState extends ConsumerState<_CountdownEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  DateTime? _date;
  bool _yearlyRepeat = false;
  bool _showAge = false;

  @override
  void initState() {
    super.initState();
    final c = widget.countdown;
    _title = TextEditingController(text: c?.title ?? '');
    _notes = TextEditingController(text: c?.notes ?? '');
    _date = _parseDate(c?.targetDate);
    _yearlyRepeat = c?.yearlyRepeat ?? false;
    _showAge = c?.showAge ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.countdown == null ? 'New countdown' : 'Edit countdown',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
              autofocus: widget.countdown == null,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _date == null
                        ? 'No date'
                        : '${_date!.year}-${_date!.month}-${_date!.day}',
                  ),
                ),
                TextButton(
                  onPressed: _pickDate,
                  child: const Text('Pick date'),
                ),
              ],
            ),
            SwitchListTile(
              title: const Text('Repeats yearly'),
              value: _yearlyRepeat,
              onChanged: (v) => setState(() => _yearlyRepeat = v),
            ),
            SwitchListTile(
              title: const Text('Show age'),
              value: _showAge,
              onChanged: (v) => setState(() => _showAge = v),
            ),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Title is required.')));
      return;
    }
    final targetDate = _date == null
        ? null
        : '${_date!.year.toString().padLeft(4, '0')}-'
              '${_date!.month.toString().padLeft(2, '0')}-'
              '${_date!.day.toString().padLeft(2, '0')}';
    final repo = ref.read(countdownRepositoryProvider);
    final existing = widget.countdown;
    if (existing == null) {
      await repo.createCountdown(
        title: title,
        targetDate: targetDate,
        yearlyRepeat: _yearlyRepeat,
        showAge: _showAge,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
    } else {
      await repo.updateCountdown(
        existing.id,
        title: title,
        targetDate: () => targetDate,
        yearlyRepeat: _yearlyRepeat,
        showAge: _showAge,
        notes: () => _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }
}

DateTime? _parseDate(String? targetDate) {
  if (targetDate == null || targetDate.isEmpty) return null;
  final p = targetDate.split('-');
  if (p.length != 3) return null;
  final y = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  final d = int.tryParse(p[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}
