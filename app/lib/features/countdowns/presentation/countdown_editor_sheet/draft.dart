part of '../countdown_editor_sheet.dart';

extension _CountdownEditorDraft on _CountdownEditorSheetState {
  String get _draftEntityId => widget.countdown?.id ?? 'new';

  void _initFromArgs() {
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

  String _expectedSheet() => widget.countdown == null
      ? 'countdown_new'
      : 'countdown:${widget.countdown!.id}';
}
