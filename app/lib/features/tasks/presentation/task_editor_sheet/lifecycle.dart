part of '../task_editor_sheet.dart';

mixin _TaskEditorLifecycle on _TaskEditorStateBase {
  String get _draftEntityId => widget.task?.id ?? 'new';

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    final d = widget.restoredDraft;
    _title = TextEditingController(
      text: (d?['title'] as String?) ?? t?.title ?? '',
    );
    _notes = TextEditingController(
      text: (d?['notes'] as String?) ?? t?.notes ?? '',
    );
    _tags = TextEditingController(text: (d?['tags'] as String?) ?? '');
    _listId = (d?['listId'] as String?) ?? t?.listId;
    _priority = (d?['priority'] as num?)?.toInt() ?? t?.priority ?? 0;
    _dueDate = (d?['dueDate'] as String?) ?? t?.dueDate;
    _plannedDate = (d?['plannedDate'] as String?) ?? t?.plannedDate;
    _plannedStart = (d?['plannedStart'] as String?) ?? t?.plannedStart;
    _plannedEnd = (d?['plannedEnd'] as String?) ?? t?.plannedEnd;
    _rrule = (d?['rrule'] as String?) ?? t?.rrule;
    _customRrule =
        _rrule != null &&
        !_TaskEditorStateBase._repeatPresets.containsValue(_rrule);
    _rruleText.text = _rrule ?? '';
    _dueTime = (d?['dueTime'] as num?)?.toInt() ?? t?.dueTime;
    _pinned = (d?['pinned'] as bool?) ?? t?.pinned ?? false;
    _alarmPreset = (d?['alarmPreset'] as String?) ?? t?.alarmPreset;
    final draftReminders = (d?['reminders'] as List?)
        ?.whereType<num>()
        .map((e) => e.toInt())
        .toList();
    _reminders = draftReminders != null && draftReminders.isNotEmpty
        ? draftReminders
        : (t?.reminders == null || t!.reminders!.trim().isEmpty
              ? const [0]
              : parseReminderOffsets(t.reminders));
    for (final c in [_title, _notes, _tags]) {
      c.addListener(_queueDraft);
    }
    if (d == null && t == null) Future.microtask(_preloadDraft);
  }

  Future<void> _preloadDraft() async {
    if (!mounted || _title.text.isNotEmpty || _notes.text.isNotEmpty) return;
    try {
      final draft = await ref.read(draftStoreProvider).load('task', 'new');
      if (draft == null || !mounted) return;
      if (draftIsExpired(
        draft.updatedAtMs,
        DateTime.now().toUtc().millisecondsSinceEpoch,
      )) {
        return;
      }
      final j = draft.json;
      final title = j['title'] as String?;
      if (title == null || title.isEmpty) return;
      setState(() {
        _title.text = title;
        _notes.text = (j['notes'] as String?) ?? '';
        _tags.text = (j['tags'] as String?) ?? '';
        _listId = j['listId'] as String?;
        _priority = (j['priority'] as num?)?.toInt() ?? 0;
        _dueDate = j['dueDate'] as String?;
        _plannedDate = j['plannedDate'] as String?;
        _plannedStart = j['plannedStart'] as String?;
        _plannedEnd = j['plannedEnd'] as String?;
        _rrule = j['rrule'] as String?;
        _customRrule =
            _rrule != null &&
            !_TaskEditorStateBase._repeatPresets.containsValue(_rrule);
        _rruleText.text = _rrule ?? '';
        _dueTime = (j['dueTime'] as num?)?.toInt();
        _pinned = (j['pinned'] as bool?) ?? false;
        _alarmPreset = j['alarmPreset'] as String?;
      });
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _saver ??= DraftAutosaver(
      ref.read(draftStoreProvider),
      'task',
      _draftEntityId,
    );
    Future.microtask(() async {
      try {
        final repo = await ref.read(settingsRepositoryProvider.future);
        _settings = repo;
        await repo.setOpenSheet(
          widget.task == null ? 'task_new' : 'task:${widget.task!.id}',
        );
      } catch (_) {}
    });
  }

  void _queueDraft() {
    _saver?.changed(
      () => {
        'title': _title.text,
        'notes': _notes.text,
        'tags': _tags.text,
        'listId': _listId,
        'priority': _priority,
        'dueDate': _dueDate,
        'plannedDate': _plannedDate,
        'plannedStart': _plannedStart,
        'plannedEnd': _plannedEnd,
        'rrule': _rrule,
        'dueTime': _dueTime,
        'pinned': _pinned,
        'alarmPreset': _alarmPreset,
        'reminders': _reminders,
        'parentId': widget.parentId,
      },
    );
  }

  String _expectedSheet() =>
      widget.task == null ? 'task_new' : 'task:${widget.task!.id}';

  @override
  void dispose() {
    if (!_saved) {
      final snapshot = {
        'title': _title.text,
        'notes': _notes.text,
        'tags': _tags.text,
        'listId': _listId,
        'priority': _priority,
        'dueDate': _dueDate,
        'plannedDate': _plannedDate,
        'plannedStart': _plannedStart,
        'plannedEnd': _plannedEnd,
        'rrule': _rrule,
        'dueTime': _dueTime,
        'pinned': _pinned,
        'alarmPreset': _alarmPreset,
        'reminders': _reminders,
        'parentId': widget.parentId,
      };
      _saver?.changed(() => snapshot);
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
    _tags.dispose();
    _rruleText.dispose();
    super.dispose();
  }
}
