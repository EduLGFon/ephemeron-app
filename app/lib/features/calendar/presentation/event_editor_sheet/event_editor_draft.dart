// Draft restore/autosave and small state helpers for the event editor,
// split from event_editor_state.dart as an extension on the state class.
part of '../event_editor_sheet.dart';

extension on _EventEditorState {
  String get _draftEntityId => widget.event?.id ?? 'new';

  bool get _isMicrosoftEvent {
    final e = widget.event;
    if (e == null) return false;
    final cals = ref.read(calendarsProvider).value ?? const <Calendar>[];
    Calendar? cal;
    for (final c in cals) {
      if (c.id == e.calendarId) {
        cal = c;
        break;
      }
    }
    if (cal == null && _calendarId != null) {
      for (final c in cals) {
        if (c.id == _calendarId) {
          cal = c;
          break;
        }
      }
    }
    return isMicrosoftEvent(
      eventMicrosoftAccount: e.microsoftAccount,
      calendarSource: cal?.source,
      calendarMicrosoftAccount: cal?.microsoftAccount,
    );
  }

  Future<void> _preloadDraft() async {
    if (!mounted || _title.text.isNotEmpty) return;
    try {
      final draft = await ref.read(draftStoreProvider).load('event', 'new');
      if (draft == null || !mounted || _title.text.isNotEmpty) return;
      if (draftIsExpired(
        draft.updatedAtMs,
        DateTime.now().toUtc().millisecondsSinceEpoch,
      )) {
        return;
      }
      _applyDraft(draft.json);
    } catch (_) {}
  }

  Map<String, dynamic> _snapshot() => {
    'title': _title.text,
    'location': _location.text,
    'notes': _notes.text,
    'attendees': _attendees.text,
    'calendarId': _calendarId,
    'allDay': _allDay,
    'colorId': _colorId,
    'tzId': _tzId,
    'addMeet': _addMeet,
    'reminders': _reminders,
    'alarmPreset': _alarmPreset,
    'startMs': _start.millisecondsSinceEpoch,
    'endMs': _end.millisecondsSinceEpoch,
    'rrule': _rrule,
  };

  void _queueDraft() => _saver?.changed(_snapshot);

  String _expectedSheet() =>
      widget.event == null ? 'event_new' : 'event:${widget.event!.id}';
}
