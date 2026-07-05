import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../application/countdown_providers.dart';
import '../domain/countdown_type.dart';

Future<void> showCountdownFormSheet(
  BuildContext context, {
  required CountdownType type,
  Countdown? existingCountdown,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) =>
        CountdownFormSheet(type: type, existingCountdown: existingCountdown),
  );
}

class CountdownFormSheet extends ConsumerStatefulWidget {
  const CountdownFormSheet({
    required this.type,
    this.existingCountdown,
    super.key,
  });

  final CountdownType type;
  final Countdown? existingCountdown;

  @override
  ConsumerState<CountdownFormSheet> createState() => _CountdownFormSheetState();
}

class _CountdownFormSheetState extends ConsumerState<CountdownFormSheet> {
  late final _titleController = TextEditingController(
    text: widget.existingCountdown?.title,
  );
  late DateTime _targetDate =
      widget.existingCountdown?.targetDate ?? DateTime.now();
  late bool _showAge = widget.existingCountdown?.showAge ?? false;
  late bool _isYearly =
      widget.existingCountdown?.isYearly ?? widget.type.isYearlyByDefault;
  bool _isSaving = false;

  bool get _isEditing => widget.existingCountdown != null;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEditing
                  ? 'Edit ${widget.type.label.toLowerCase()}'
                  : 'New ${widget.type.label.toLowerCase()}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              autofocus: !_isEditing,
              decoration: const InputDecoration(labelText: 'Title'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_targetDate.year}-${_targetDate.month.toString().padLeft(2, '0')}-'
                    '${_targetDate.day.toString().padLeft(2, '0')}',
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                TextButton(onPressed: _pickDate, child: const Text('Set date')),
              ],
            ),
            if (widget.type.supportsAge) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show age'),
                subtitle: Text(
                  _showAge
                      ? 'The year above is used to calculate age'
                      : 'Year is ignored — only month and day count',
                ),
                value: _showAge,
                onChanged: (value) => setState(() => _showAge = value),
              ),
            ],
            if (widget.type == CountdownType.custom) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Repeats yearly'),
                value: _isYearly,
                onChanged: (value) => setState(() => _isYearly = value),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Alerts: 3 days before and on the day',
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isSaving || _titleController.text.trim().isEmpty
                  ? null
                  : _save,
              child: _isSaving
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEditing ? 'Save' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _targetDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 365 * 100)),
    );
    if (date != null) setState(() => _targetDate = date);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final repo = ref.read(countdownRepositoryProvider);
    try {
      if (_isEditing) {
        await repo.updateCountdown(
          widget.existingCountdown!.id,
          title: _titleController.text.trim(),
          targetDate: _targetDate,
          isYearly: _isYearly,
          showAge: _showAge,
        );
      } else {
        await repo.createCountdown(
          title: _titleController.text.trim(),
          type: widget.type,
          targetDate: _targetDate,
          isYearly: _isYearly,
          showAge: _showAge,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
