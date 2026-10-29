// Recurrence model
enum RecurrenceType { none, daily, weekly, monthly, yearly }

enum RepeatDuration { forever, specificTimes, until }

enum MonthlyRepeatMode { dayOfMonth, dayOfWeek, selectDates }

class RecurrenceConfig {
  const RecurrenceConfig({
    this.type = RecurrenceType.none,
    this.interval = 1,
    this.monthlyMode = MonthlyRepeatMode.dayOfMonth,
    this.duration = RepeatDuration.forever,
    this.repeatTimes = 10,
    this.untilDate,
  });

  final RecurrenceType type;
  final int interval;
  final MonthlyRepeatMode monthlyMode;
  final RepeatDuration duration;
  final int repeatTimes;
  final DateTime? untilDate;

  List<String> toRruleList(DateTime start) {
    if (type == RecurrenceType.none) return const [];
    final parts = <String>[];
    switch (type) {
      case RecurrenceType.daily:
        parts.add('FREQ=DAILY');
        if (interval > 1) parts.add('INTERVAL=$interval');
        break;
      case RecurrenceType.weekly:
        parts.add('FREQ=WEEKLY');
        if (interval > 1) parts.add('INTERVAL=$interval');
        break;
      case RecurrenceType.monthly:
        parts.add('FREQ=MONTHLY');
        if (interval > 1) parts.add('INTERVAL=$interval');
        if (monthlyMode == MonthlyRepeatMode.dayOfWeek) {
          final ordinal = ((start.day - 1) ~/ 7) + 1;
          final weekdayMap = {
            1: 'MO',
            2: 'TU',
            3: 'WE',
            4: 'TH',
            5: 'FR',
            6: 'SA',
            7: 'SU'
          };
          final weekdayStr = weekdayMap[start.weekday];
          parts.add('BYDAY=$ordinal$weekdayStr');
        } else {
          parts.add('BYMONTHDAY=${start.day}');
        }
        break;
      case RecurrenceType.yearly:
        parts.add('FREQ=YEARLY');
        if (interval > 1) parts.add('INTERVAL=$interval');
        break;
      case RecurrenceType.none:
        return const [];
    }

    if (duration == RepeatDuration.specificTimes) {
      parts.add('COUNT=$repeatTimes');
    } else if (duration == RepeatDuration.until && untilDate != null) {
      final utcUntil = untilDate!.toUtc();
      final formatted = '${utcUntil.year.toString().padLeft(4, '0')}'
          '${utcUntil.month.toString().padLeft(2, '0')}'
          '${utcUntil.day.toString().padLeft(2, '0')}T'
          '${utcUntil.hour.toString().padLeft(2, '0')}'
          '${utcUntil.minute.toString().padLeft(2, '0')}'
          '${utcUntil.second.toString().padLeft(2, '0')}Z';
      parts.add('UNTIL=$formatted');
    }

    return ['RRULE:${parts.join(';')}'];
  }

  static RecurrenceConfig fromRruleList(List<String>? rruleList) {
    if (rruleList == null || rruleList.isEmpty) return const RecurrenceConfig();

    final rruleLine = rruleList.firstWhere((line) => line.startsWith('RRULE:'),
        orElse: () => '');
    if (rruleLine.isEmpty) return const RecurrenceConfig();

    final rruleContent = rruleLine.substring(6);
    final parts = rruleContent.split(';');
    final map = <String, String>{};
    for (final part in parts) {
      final kv = part.split('=');
      if (kv.length == 2) {
        map[kv[0].toUpperCase()] = kv[1];
      }
    }

    final freq = map['FREQ'];
    if (freq == null) return const RecurrenceConfig();

    RecurrenceType type = RecurrenceType.none;
    if (freq == 'DAILY') {
      type = RecurrenceType.daily;
    } else if (freq == 'WEEKLY') {
      type = RecurrenceType.weekly;
    } else if (freq == 'MONTHLY') {
      type = RecurrenceType.monthly;
    } else if (freq == 'YEARLY') {
      type = RecurrenceType.yearly;
    }

    if (type == RecurrenceType.none) return const RecurrenceConfig();

    final interval = int.tryParse(map['INTERVAL'] ?? '') ?? 1;

    MonthlyRepeatMode monthlyMode = MonthlyRepeatMode.dayOfMonth;
    if (type == RecurrenceType.monthly) {
      if (map.containsKey('BYDAY')) {
        monthlyMode = MonthlyRepeatMode.dayOfWeek;
      } else {
        monthlyMode = MonthlyRepeatMode.dayOfMonth;
      }
    }

    RepeatDuration duration = RepeatDuration.forever;
    int repeatTimes = 10;
    DateTime? untilDate;

    if (map.containsKey('COUNT')) {
      duration = RepeatDuration.specificTimes;
      repeatTimes = int.tryParse(map['COUNT']!) ?? 10;
    } else if (map.containsKey('UNTIL')) {
      duration = RepeatDuration.until;
      final untilStr = map['UNTIL']!;
      if (untilStr.length >= 8) {
        final year = int.tryParse(untilStr.substring(0, 4));
        final month = int.tryParse(untilStr.substring(4, 6));
        final day = int.tryParse(untilStr.substring(6, 8));
        if (year != null && month != null && day != null) {
          untilDate = DateTime(year, month, day);
        }
      }
    }

    return RecurrenceConfig(
      type: type,
      interval: interval,
      monthlyMode: monthlyMode,
      duration: duration,
      repeatTimes: repeatTimes,
      untilDate: untilDate,
    );
  }
}