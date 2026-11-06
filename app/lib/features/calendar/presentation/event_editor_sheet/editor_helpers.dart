// Private helpers shared by the event editor library parts: date key
// parsing, date/time formatting, RRULE summaries, repeat presets, and
// the original occurrence start used when editing recurring events.
part of '../event_editor_sheet.dart';

/// Parses an all-day `YYYY-MM-DD` key into local midnight.
DateTime? _parseDateKey(String? value) {
  if (value == null) return null;
  final parts = value.split('-');
  if (parts.length != 3) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}

String _summarizeRrule(BuildContext context, String rrule) {
  try {
    final r = RecurrenceRule.parse(rrule);
    final freq = r.freq[0] + r.freq.substring(1).toLowerCase();
    final interval = r.interval > 1 ? ' every ${r.interval}' : '';
    final days = r.byDay.isNotEmpty ? ' on ${r.byDay.join(', ')}' : '';
    final end = r.count != null
        ? ' for ${r.count} times'
        : r.untilUtc != null
        ? ' until ${DeviceDateFormat.yMMMd(context).format(r.untilUtc!.toLocal())}'
        : r.untilDate != null
        ? ' until ${r.untilDate}'
        : '';
    return '$freq$interval$days$end';
  } catch (_) {
    return rrule;
  }
}

const _repeatPresets = {
  'Does not repeat': null,
  'Daily': 'FREQ=DAILY',
  'Weekly': 'FREQ=WEEKLY',
  'Monthly': 'FREQ=MONTHLY',
  'Yearly': 'FREQ=YEARLY',
  'Last day of month': 'FREQ=MONTHLY;BYMONTHDAY=-1',
};

// The series start the repository expects when editing an occurrence.
DateTime _originalStartOf(Event event) {
  if (event.startUtc != null) {
    return DateTime.fromMillisecondsSinceEpoch(event.startUtc!, isUtc: true);
  }
  final date = _parseDateKey(event.startDate);
  if (date != null) return DateTime.utc(date.year, date.month, date.day);
  return DateTime.now().toUtc();
}

String _fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _fmtTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
