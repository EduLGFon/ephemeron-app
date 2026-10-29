// Natural date/time parsing for English and Portuguese. Pure Dart, offline.
// Matching is case-insensitive; the returned title keeps original casing.

class ParsedNatural {
  ParsedNatural({required this.title, this.due, this.rrule});
  final String title;
  final DateTime? due;
  final String? rrule;
}

const _weekdayMap = {
  'monday': DateTime.monday,
  'mon': DateTime.monday,
  'segunda': DateTime.monday,
  'seg': DateTime.monday,
  'tuesday': DateTime.tuesday,
  'terca': DateTime.tuesday,
  'terça': DateTime.tuesday,
  'ter': DateTime.tuesday,
  'wednesday': DateTime.wednesday,
  'quarta': DateTime.wednesday,
  'qua': DateTime.wednesday,
  'thursday': DateTime.thursday,
  'quinta': DateTime.thursday,
  'qui': DateTime.thursday,
  'friday': DateTime.friday,
  'sexta': DateTime.friday,
  'sex': DateTime.friday,
  'saturday': DateTime.saturday,
  'sabado': DateTime.saturday,
  'sábado': DateTime.saturday,
  'sab': DateTime.saturday,
  'sunday': DateTime.sunday,
  'domingo': DateTime.sunday,
  'dom': DateTime.sunday,
};

const _weekdayCode = {
  DateTime.monday: 'MO',
  DateTime.tuesday: 'TU',
  DateTime.wednesday: 'WE',
  DateTime.thursday: 'TH',
  DateTime.friday: 'FR',
  DateTime.saturday: 'SA',
  DateTime.sunday: 'SU',
};

String _cut(String src, Pattern pattern) =>
    src.replaceAll(pattern, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

ParsedNatural parseNatural(String input, {DateTime? now}) {
  now ??= DateTime.now();
  var working = input.trim();
  DateTime? date;
  int? hour;
  int minute = 0;
  String? rrule;

  final dailyRe = RegExp(
      r'every day|todo dia|todos os dias|diariamente',
      caseSensitive: false);
  if (dailyRe.hasMatch(working)) {
    rrule = 'FREQ=DAILY';
    working = _cut(working, dailyRe);
  }
  final everyWd = RegExp(r'(?:every|toda|todo)\s+([a-zà-ú]+)',
      caseSensitive: false).firstMatch(working);
  if (everyWd != null) {
    final wd = _weekdayMap[everyWd.group(1)!.toLowerCase()];
    if (wd != null && rrule == null) {
      rrule = 'FREQ=WEEKLY;BYDAY=${_weekdayCode[wd]}';
      working = _cut(working, everyWd.group(0)!);
    }
  }

  final timeH =
      RegExp(r'(\d{1,2})h(\d{2})?', caseSensitive: false).firstMatch(working);
  if (timeH != null) {
    hour = int.parse(timeH.group(1)!);
    if (timeH.group(2) != null) minute = int.parse(timeH.group(2)!);
    working = _cut(working, timeH.group(0)!);
  } else {
    final timeColon = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(working);
    if (timeColon != null) {
      hour = int.parse(timeColon.group(1)!);
      minute = int.parse(timeColon.group(2)!);
      working = _cut(working, timeColon.group(0)!);
    } else {
      final timeAmPm = RegExp(r'(\d{1,2})\s?(am|pm)', caseSensitive: false)
          .firstMatch(working);
      if (timeAmPm != null) {
        hour = int.parse(timeAmPm.group(1)!);
        if (timeAmPm.group(2)!.toLowerCase() == 'pm' && hour < 12) hour += 12;
        working = _cut(working, timeAmPm.group(0)!);
      }
    }
  }

  final todayRe =
      RegExp(r'\btoday\b|\bhoje\b', caseSensitive: false);
  final tomorrowRe = RegExp(r'\btomorrow\b|\bamanh[ãa]\b', caseSensitive: false);
  if (todayRe.hasMatch(working)) {
    date = DateTime(now.year, now.month, now.day);
    working = _cut(working, todayRe);
  } else if (tomorrowRe.hasMatch(working)) {
    date = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    working = _cut(working, tomorrowRe);
  }

  final inHours = RegExp(r'in\s+(\d+)\s*hours?|em\s+(\d+)\s*horas?',
          caseSensitive: false)
      .firstMatch(working);
  if (inHours != null) {
    final n = int.parse((inHours.group(1) ?? inHours.group(2))!);
    date = now.add(Duration(hours: n));
    working = _cut(working, inHours.group(0)!);
  }
  final inDays = RegExp(r'in\s+(\d+)\s*days?|em\s+(\d+)\s*dias?',
          caseSensitive: false)
      .firstMatch(working);
  if (inDays != null) {
    final n = int.parse((inDays.group(1) ?? inDays.group(2))!);
    date = DateTime(now.year, now.month, now.day).add(Duration(days: n));
    working = _cut(working, inDays.group(0)!);
  }

  final nextWd = RegExp(
          r'next\s+([a-zà-ú]+)|pr[óo]xim[oa]\s+([a-zà-ú]+)',
          caseSensitive: false)
      .firstMatch(working);
  if (nextWd != null) {
    final name =
        (nextWd.group(1) ?? nextWd.group(2) ?? '').toLowerCase();
    final wd = _weekdayMap[name];
    if (wd != null) {
      date = _nextWeekday(now, wd);
      working = _cut(working, nextWd.group(0)!);
    }
  }

  if (date != null && hour != null) {
    date = DateTime(date.year, date.month, date.day, hour, minute);
  } else if (date == null && hour != null) {
    var d = DateTime(now.year, now.month, now.day, hour, minute);
    if (d.isBefore(now)) d = d.add(const Duration(days: 1));
    date = d;
  }

  final title = working.replaceAll(RegExp(r'\s+'), ' ').trim();
  return ParsedNatural(title: title.isEmpty ? input.trim() : title, due: date, rrule: rrule);
}

DateTime _nextWeekday(DateTime now, int weekday) {
  var d = DateTime(now.year, now.month, now.day);
  while (d.weekday != weekday) {
    d = d.add(const Duration(days: 1));
  }
  if (d.difference(DateTime(now.year, now.month, now.day)).inDays == 0) {
    d = d.add(const Duration(days: 7));
  }
  return d;
}
