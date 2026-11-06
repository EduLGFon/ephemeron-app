part of '../task_editor_sheet.dart';

mixin _TaskEditorSave on _TaskEditorStateBase {
  bool _isValidRrule(String value);
  String get _draftEntityId;

  bool get _isMicrosoftTask {
    final t = widget.task;
    if (t == null) return false;
    final lists = ref.read(taskListsProvider).value ?? const <TaskList>[];
    TaskList? list;
    for (final l in lists) {
      if (l.id == t.listId) {
        list = l;
        break;
      }
    }
    return isMicrosoftTask(
      taskMicrosoftAccount: t.microsoftAccount,
      listMicrosoftAccount: list?.microsoftAccount,
    );
  }

  // ignore: unused_element
  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Title is required.')));
      return;
    }
    // Moment of need, advisory only: the save always proceeds.
    if (_reminders.isNotEmpty || _alarmPreset != null) {
      final preset = AlarmPreset.tryParse(_alarmPreset);
      await AppPermissions.ensureAlarmPrereqs(
        context,
        exactAlarm: preset?.needsAlarmClock ?? false,
        fullScreen: preset?.usesFullScreen ?? false,
      );
      if (!mounted) return;
    }
    if (_plannedStart != null && _plannedEnd != null) {
      final s = DateTime.tryParse(_plannedStart!);
      final e = DateTime.tryParse(_plannedEnd!);
      if (s != null && e != null && !e.isAfter(s)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Planned end must be after start.')),
          );
        }
        return;
      }
    }
    if (_rrule != null &&
        _rrule!.trim().isNotEmpty &&
        !_isValidRrule(_rrule!)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid recurrence rule.')),
        );
      }
      return;
    }
    if (widget.task != null && _isMicrosoftTask) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microsoft tasks cannot be edited.')),
        );
      }
      return;
    }
    final repo = ref.read(taskRepositoryProvider);
    final tagNames = _tags.text
        .split(RegExp(r'[,\s]+'))
        .map((s) => s.replaceAll('#', '').trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final existing = widget.task;
    // A timed planned interval replaces the legacy all-day planned date.
    final plannedDate = _plannedStart == null ? _plannedDate : null;
    if (existing == null) {
      await repo.createTask(
        title: title,
        listId: _listId,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        priority: _priority,
        dueDate: _dueDate,
        plannedDate: plannedDate,
        plannedStart: _plannedStart,
        plannedEnd: _plannedEnd,
        rrule: _rrule,
        dueTime: _dueTime,
        pinned: _pinned,
        parentId: widget.parentId,
        tags: tagNames,
        alarmPreset: _alarmPreset,
        reminders: encodeReminderOffsets(_reminders),
      );
    } else {
      if (existing.listId != _listId) {
        try {
          await repo.moveTasks([existing.id], _listId);
        } on SourceMoveException catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(e.message)));
          }
          return;
        }
      }
      await repo.updateTask(
        existing.id,
        title: title,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        priority: _priority,
        dueDate: () => _dueDate,
        plannedDate: () => plannedDate,
        plannedStart: () => _plannedStart,
        plannedEnd: () => _plannedEnd,
        rrule: () => _rrule,
        dueTime: () => _dueTime,
        pinned: _pinned,
        alarmPreset: () => _alarmPreset,
        reminders: () => encodeReminderOffsets(_reminders),
      );
      if (tagNames.isNotEmpty) {
        await repo.setTaskTags(existing.id, tagNames);
      }
    }
    try {
      ref.read(occurrenceDirtyProvider.notifier).markDirty();
    } catch (_) {}
    _saved = true;
    try {
      await ref.read(draftStoreProvider).clear('task', _draftEntityId);
      final srepo = await ref.read(settingsRepositoryProvider.future);
      final expected = widget.task == null
          ? 'task_new'
          : 'task:${widget.task!.id}';
      if (srepo.openSheet == expected) await srepo.setOpenSheet(null);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }
}
