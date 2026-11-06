// Save flow and date/time picker plumbing for the event editor state,
// split out as an extension on the state class (same convention as
// sync_engine's pull/push parts). Members stay library-private.
part of '../event_editor_sheet.dart';

extension on _EventEditorState {
  Future<void> _clearDraftAfterSave() async {
    _saved = true;
    try {
      await ref.read(draftStoreProvider).clear('event', _draftEntityId);
      final srepo = await ref.read(settingsRepositoryProvider.future);
      final expected = widget.event == null
          ? 'event_new'
          : 'event:${widget.event!.id}';
      if (srepo.openSheet == expected) await srepo.setOpenSheet(null);
    } catch (_) {}
  }

  /// Trims the description and caps the event column at 8000 chars so the
  /// full text can live in a linked overflow note.
  ({String? full, String? stored}) _notesPayload() {
    final full = _notes.text.trim();
    if (full.isEmpty) return (full: null, stored: null);
    return (
      full: full,
      stored: full.length > 8000
          ? '${full.substring(0, 8000)}\n(continued in Ephemeron)'
          : full,
    );
  }

  Future<void> _persistOverflow(String eventId, String? fullNotes) async {
    if (fullNotes == null || fullNotes.length <= 8000) return;
    final noteId = await ref
        .read(noteRepositoryProvider)
        .ensureOverflowNote(eventId, fullNotes);
    await ref.read(eventRepositoryProvider).setNotesOverflow(eventId, noteId);
  }

  Future<void> _pickDate(bool isStart) async {
    SettingsRepository? settings;
    try {
      settings = await ref.read(settingsRepositoryProvider.future);
    } catch (_) {}
    if (!mounted) return;
    final key = isStart
        ? PickerMemoryKeys.eventStart
        : PickerMemoryKeys.eventEnd;
    final d = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : _end,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    _changed(() {
      if (isStart) {
        _start = DateTime(
          d.year,
          d.month,
          d.day,
          _allDay ? 0 : _start.hour,
          _allDay ? 0 : _start.minute,
        );
        if (_end.isBefore(_start)) {
          _end = _allDay ? _start : _start.add(const Duration(hours: 1));
        }
      } else {
        _end = DateTime(
          d.year,
          d.month,
          d.day,
          _allDay ? 0 : _end.hour,
          _allDay ? 0 : _end.minute,
        );
        if (_end.isBefore(_start)) {
          _end = _allDay ? _start : _start.add(const Duration(hours: 1));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('End was before start; adjusted.')),
          );
        }
      }
    });
    try {
      final dt = isStart ? _start : _end;
      await settings?.setPickerDateTime(key, dt.toIso8601String());
    } catch (_) {}
  }

  Future<void> _pickTime(bool isStart) async {
    SettingsRepository? settings;
    try {
      settings = await ref.read(settingsRepositoryProvider.future);
    } catch (_) {}
    if (!mounted) return;
    final key = isStart
        ? PickerMemoryKeys.eventStart
        : PickerMemoryKeys.eventEnd;
    final base = isStart ? _start : _end;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
    );
    if (t == null) return;
    _changed(() {
      if (isStart) {
        final dur = _end.difference(_start);
        _start = DateTime(
          _start.year,
          _start.month,
          _start.day,
          t.hour,
          t.minute,
        );
        _end = _start.add(dur);
      } else {
        _end = DateTime(_end.year, _end.month, _end.day, t.hour, t.minute);
      }
    });
    try {
      final dt = isStart ? _start : _end;
      await settings?.setPickerDateTime(key, dt.toIso8601String());
    } catch (_) {}
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Title is required.')));
      return;
    }
    if (_calendarId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a calendar.')));
      return;
    }
    // Moment of need: reminders/alarms only prompt here, at save time.
    // Advisory only: the save always proceeds, alerts may stay silent.
    if (_reminders.isNotEmpty || _alarmPreset != null) {
      final preset = AlarmPreset.tryParse(_alarmPreset);
      await AppPermissions.ensureAlarmPrereqs(
        context,
        exactAlarm: preset?.needsAlarmClock ?? false,
        fullScreen: preset?.usesFullScreen ?? false,
      );
      if (!mounted) return;
    }
    if (widget.event != null && _isMicrosoftEvent) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microsoft events cannot be edited.')),
        );
      }
      return;
    }
    final repo = ref.read(eventRepositoryProvider);
    final existing = widget.event;
    if (existing != null &&
        _calendarId != null &&
        _calendarId != existing.calendarId) {
      try {
        await repo.moveEventToCalendar(existing.id, _calendarId!);
      } on SourceMoveException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        }
        return;
      }
    }
    // Conflict hint: warn if overlapping a busy event.
    if (!_allDay) {
      final overlaps = await repo.overlappingEvents(
        calendarId: _calendarId!,
        startUtc: _start.toUtc(),
        endUtc: _end.toUtc(),
        excludeId: widget.event?.id,
      );
      if (overlaps.isNotEmpty && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Scheduling conflict'),
            content: Text(
              'This overlaps ${overlaps.length} existing event(s). Save anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Save'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }
    }
    final settings = await ref.read(settingsRepositoryProvider.future);
    _calendarId ??= settings.defaultCalendarId;
    final notesPayload = _notesPayload();
    final startDateKey = _allDay ? _fmtDate(_start) : null;
    final endDateKey = _allDay
        ? _fmtDate(DateTime(_end.year, _end.month, _end.day + 1))
        : null;
    if (existing == null || existing.rrule == null) {
      if (existing == null) {
        final eventId = await repo.createEvent(
          calendarId: _calendarId!,
          title: title,
          startUtc: _allDay ? null : _start.toUtc(),
          endUtc: _allDay ? null : _end.toUtc(),
          startDate: startDateKey,
          endDate: endDateKey,
          allDay: _allDay,
          // SECURITY: store null (floating local time) for device-created
          // events. DateTime.now().timeZoneName yields abbreviations like
          // "-03" that are not IANA ids and crash tz.getLocation lookups.
          tzId: _tzId,
          colorId: _colorId,
          createMeet: _addMeet,
          rrule: _rrule,
          location: _location.text.trim().isEmpty
              ? null
              : _location.text.trim(),
          notes: notesPayload.stored,
          reminders: encodeReminderOffsets(_reminders),
          alarmPreset: _alarmPreset,
        );
        await _persistOverflow(eventId, notesPayload.full);
        await repo.setAttendees(eventId, _attendees.text.split(','));
      } else {
        final eventId = await repo.editOccurrence(
          existing.id,
          _originalStartOf(existing),
          scope: EditScope.all,
          title: title,
          startUtc: _allDay ? null : _start.toUtc(),
          endUtc: _allDay ? null : _end.toUtc(),
          startDate: startDateKey,
          endDate: endDateKey,
          location: _location.text.trim().isEmpty
              ? null
              : _location.text.trim(),
          colorId: _colorId,
          tzId: _tzId,
          createMeet: _addMeet,
          reminders: () => encodeReminderOffsets(_reminders),
          alarmPreset: () => _alarmPreset,
          notes: () => notesPayload.stored,
        );
        await _persistOverflow(eventId, notesPayload.full);
      }
      if (existing != null) {
        await repo.setAttendees(existing.id, _attendees.text.split(','));
      }
      await _clearDraftAfterSave();
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (!mounted) return;
    final scope = await showScopeSheet(
      context,
      allowSingle: _rrule == existing.rrule,
    );
    if (scope == null) return;
    if (!mounted) return;
    final datesChanged = _allDay
        ? startDateKey != existing.startDate || endDateKey != existing.endDate
        : _start.toUtc().millisecondsSinceEpoch != existing.startUtc ||
              _end.toUtc().millisecondsSinceEpoch != existing.endUtc;
    if (scope == EditScope.all && datesChanged) {
      final keep =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Keep per-event changes?'),
              content: const Text(
                'Some occurrences were changed individually.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Keep'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Reset'),
                ),
              ],
            ),
          ) ??
          true;
      if (!mounted) return;
      final eventId = await repo.editOccurrence(
        existing.id,
        _originalStartOf(existing),
        scope: EditScope.all,
        title: title,
        startUtc: _allDay ? null : _start.toUtc(),
        endUtc: _allDay ? null : _end.toUtc(),
        startDate: startDateKey,
        endDate: endDateKey,
        rrule: () => _rrule,
        resetExceptions: !keep,
        notes: () => notesPayload.stored,
      );
      await _persistOverflow(eventId, notesPayload.full);
      await repo.setAttendees(existing.id, _attendees.text.split(','));
      await _clearDraftAfterSave();
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final eventId = await repo.editOccurrence(
      existing.id,
      _originalStartOf(existing),
      scope: scope,
      title: title,
      startUtc: _allDay ? null : _start.toUtc(),
      endUtc: _allDay ? null : _end.toUtc(),
      startDate: startDateKey,
      endDate: endDateKey,
      rrule: scope == EditScope.single ? null : () => _rrule,
      notes: () => notesPayload.stored,
    );
    if (mounted) {
      await _persistOverflow(eventId, notesPayload.full);
      try {
        final range = ref.read(calendarCacheRangeProvider);
        await ref
            .read(occurrenceRepositoryProvider)
            .rebuildWindow(
              windowStartUtc: range.fromUtc,
              windowEndUtc: range.toUtc,
            );
      } catch (_) {
        // Best-effort; next navigation rebuilds.
      }
      await _clearDraftAfterSave();
      if (mounted) Navigator.of(context).pop();
    }
  }
}
