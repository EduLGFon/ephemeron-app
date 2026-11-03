// Countdown editor bottom sheet: create and edit.
import 'package:flutter/material.dart';
import 'package:ephemeron/core/time/device_date_format.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/session/session_restore.dart';
import '../../../data/drift/app_database.dart';
import '../../settings/application/settings_providers.dart';
import '../../../domain/alarms/alarm_preset.dart';
import '../../../core/platform/app_permissions.dart';
import '../../../core/ui/escape_to_close.dart';
import '../../alarms/presentation/alarm_preset_picker.dart';
import '../application/countdowns_providers.dart';

Future<void> showCountdownEditor(
  BuildContext context, {
  Countdown? countdown,
  Map<String, dynamic>? restoredDraft,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => EscapeToClose(
      child: _CountdownEditorSheet(
        countdown: countdown,
        restoredDraft: restoredDraft,
      ),
    ),
  );
}

class _CountdownEditorSheet extends ConsumerStatefulWidget {
  const _CountdownEditorSheet({this.countdown, this.restoredDraft});

  final Countdown? countdown;
  final Map<String, dynamic>? restoredDraft;

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
  int _alertOffsetDays = 3;
  int _alertHour = 9;
  int _alertMinute = 0;
  String? _alarmPreset;
  DraftAutosaver? _saver;
  bool _saved = false;
  dynamic _settings;

  String get _draftEntityId => widget.countdown?.id ?? 'new';

  Map<String, dynamic> _snapshot() => {
    'title': _title.text,
    'notes': _notes.text,
    'date': _date == null
        ? null
        : '${_date!.year.toString().padLeft(4, '0')}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}',
    'yearlyRepeat': _yearlyRepeat,
    'showAge': _showAge,
    'alertOffsetDays': _alertOffsetDays,
    'alertHour': _alertHour,
    'alertMinute': _alertMinute,
    'alarmPreset': _alarmPreset,
  };

  void _queueDraft() => _saver?.changed(_snapshot);

  void _changed(void Function() fn) {
    setState(fn);
    _queueDraft();
  }

  @override
  void initState() {
    super.initState();
    final c = widget.countdown;
    final d = widget.restoredDraft;
    _title = TextEditingController(
      text: (d?['title'] as String?) ?? c?.title ?? '',
    );
    _notes = TextEditingController(
      text: (d?['notes'] as String?) ?? c?.notes ?? '',
    );
    _date = d?['date'] != null
        ? _parseDate(d!['date'] as String?)
        : _parseDate(c?.targetDate);
    _yearlyRepeat = (d?['yearlyRepeat'] as bool?) ?? c?.yearlyRepeat ?? false;
    _showAge = (d?['showAge'] as bool?) ?? c?.showAge ?? false;
    _alertOffsetDays =
        (d?['alertOffsetDays'] as num?)?.toInt() ?? c?.alertOffsetDays ?? 3;
    final tm = c?.alertTimeMin ?? 540;
    _alertHour = (d?['alertHour'] as num?)?.toInt() ?? tm ~/ 60;
    _alertMinute = (d?['alertMinute'] as num?)?.toInt() ?? tm % 60;
    _alarmPreset = (d?['alarmPreset'] as String?) ?? c?.alarmPreset;
    for (final ctl in [_title, _notes]) {
      ctl.addListener(_queueDraft);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _saver ??= DraftAutosaver(
      ref.read(draftStoreProvider),
      'countdown',
      _draftEntityId,
    );
    Future.microtask(() async {
      try {
        final repo = await ref.read(settingsRepositoryProvider.future);
        _settings = repo;
        await repo.setOpenSheet(
          widget.countdown == null
              ? 'countdown_new'
              : 'countdown:${widget.countdown!.id}',
        );
      } catch (_) {}
    });
  }

  String _expectedSheet() => widget.countdown == null
      ? 'countdown_new'
      : 'countdown:${widget.countdown!.id}';

  @override
  void dispose() {
    if (!_saved) {
      final snap = _snapshot();
      _saver?.changed(() => snap);
    }
    _saver?.dispose();
    final settings = _settings;
    // Normal close clears the marker; process kill skips dispose
    // so the marker survives kills. Drafts are kept for preload.
    if (settings != null) {
      final expected = _expectedSheet();
      Future.microtask(() async {
        try {
          if (settings.openSheet == expected) {
            await settings.setOpenSheet(null);
          }
        } catch (_) {}
      });
    }
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
                        : DeviceDateFormat.yMMMd(context).format(_date!),
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
              onChanged: (v) => _changed(() => _yearlyRepeat = v),
            ),
            SwitchListTile(
              title: const Text('Show age'),
              value: _showAge,
              onChanged: (v) => _changed(() => _showAge = v),
            ),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Notify $_alertOffsetDays day(s) before + on the day at '
                    '${_alertHour.toString().padLeft(2, '0')}:'
                    '${_alertMinute.toString().padLeft(2, '0')}',
                  ),
                ),
                TextButton(
                  onPressed: _pickAlertTime,
                  child: const Text('Time'),
                ),
              ],
            ),
            Row(
              children: [
                const Text('Days before:'),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _alertOffsetDays,
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('On day only')),
                    DropdownMenuItem(value: 1, child: Text('1 day')),
                    DropdownMenuItem(value: 3, child: Text('3 days')),
                    DropdownMenuItem(value: 7, child: Text('7 days')),
                  ],
                  onChanged: (v) => _changed(() => _alertOffsetDays = v ?? 3),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AlarmPresetPicker(
              value: _alarmPreset,
              onChanged: (v) => _changed(() => _alarmPreset = v),
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
    if (d != null) _changed(() => _date = d);
  }

  Future<void> _pickAlertTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _alertHour, minute: _alertMinute),
    );
    if (t != null) {
      _changed(() {
        _alertHour = t.hour;
        _alertMinute = t.minute;
      });
    }
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
    // Countdown alerts always notify 3 days before and on the day, so the
    // notification prompt belongs to every save (advisory only).
    final preset = AlarmPreset.tryParse(_alarmPreset);
    await AppPermissions.ensureAlarmPrereqs(
      context,
      exactAlarm: preset?.needsAlarmClock ?? false,
      fullScreen: preset?.usesFullScreen ?? false,
    );
    if (!mounted) return;
    final repo = ref.read(countdownRepositoryProvider);
    final existing = widget.countdown;
    if (existing == null) {
      await repo.createCountdown(
        title: title,
        targetDate: targetDate,
        yearlyRepeat: _yearlyRepeat,
        showAge: _showAge,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        alertOffsetDays: _alertOffsetDays,
        alertTimeMin: _alertHour * 60 + _alertMinute,
        alarmPreset: _alarmPreset,
      );
    } else {
      await repo.updateCountdown(
        existing.id,
        title: title,
        targetDate: () => targetDate,
        yearlyRepeat: _yearlyRepeat,
        showAge: _showAge,
        notes: () => _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        alertOffsetDays: () => _alertOffsetDays,
        alertTimeMin: () => _alertHour * 60 + _alertMinute,
        alarmPreset: () => _alarmPreset,
      );
    }
    _saved = true;
    try {
      await ref.read(draftStoreProvider).clear('countdown', _draftEntityId);
      final srepo = await ref.read(settingsRepositoryProvider.future);
      final expected = widget.countdown == null
          ? 'countdown_new'
          : 'countdown:${widget.countdown!.id}';
      if (srepo.openSheet == expected) await srepo.setOpenSheet(null);
    } catch (_) {}
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
