import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

part 'recurrence_rule/parser.dart';
part 'recurrence_rule/expander.dart';
part 'recurrence_rule/matcher.dart';

const _weekdays = {
  'MO': DateTime.monday,
  'TU': DateTime.tuesday,
  'WE': DateTime.wednesday,
  'TH': DateTime.thursday,
  'FR': DateTime.friday,
  'SA': DateTime.saturday,
  'SU': DateTime.sunday,
};

class RecurrenceRule {
  RecurrenceRule({
    required this.freq,
    this.interval = 1,
    this.count,
    this.untilUtc,
    this.untilDate,
    this.byDay = const [],
    this.byMonthDay = const [],
    this.byMonth = const [],
    this.bySetPos = const [],
    this.wkst = 'MO',
    this.allDay = false,
  });

  final String freq;
  final int interval;
  final int? count;
  final DateTime? untilUtc;
  final String? untilDate;
  final List<String> byDay;
  final List<int> byMonthDay;
  final List<int> byMonth;
  final List<int> bySetPos;
  final String wkst;
  final bool allDay;

  static RecurrenceRule parse(String rrule, {bool allDay = false}) {
    _ensureTz();
    var s = rrule.trim();
    if (s.toUpperCase().startsWith('RRULE:')) s = s.substring(6);
    final parts = s.split(';');
    String freq = 'DAILY';
    int interval = 1;
    int? count;
    DateTime? untilUtc;
    String? untilDate;
    List<String> byDay = [];
    List<int> byMonthDay = [];
    List<int> byMonth = [];
    List<int> bySetPos = [];
    String wkst = 'MO';
    for (final p in parts) {
      if (p.isEmpty) continue;
      final kv = p.split('=');
      if (kv.length != 2) continue;
      final k = kv[0].toUpperCase();
      final v = kv[1];
      switch (k) {
        case 'FREQ':
          freq = v.toUpperCase();
          break;
        case 'INTERVAL':
          interval = int.tryParse(v) ?? 1;
          if (interval < 1) interval = 1;
          break;
        case 'COUNT':
          count = int.tryParse(v);
          break;
        case 'UNTIL':
          if (v.endsWith('Z') || v.contains('T')) {
            untilUtc = _parseUtc(v);
          } else {
            if (v.length == 8) {
              untilDate =
                  '${v.substring(0, 4)}-${v.substring(4, 6)}-${v.substring(6, 8)}';
            } else {
              untilDate = v;
            }
          }
          break;
        case 'BYDAY':
          byDay = v.split(',').map((e) => e.trim()).toList();
          break;
        case 'BYMONTHDAY':
          byMonthDay = v.split(',').map(int.parse).toList();
          break;
        case 'BYMONTH':
          byMonth = v.split(',').map(int.parse).toList();
          break;
        case 'BYSETPOS':
          bySetPos = v.split(',').map(int.parse).toList();
          break;
        case 'WKST':
          wkst = v.toUpperCase();
          break;
      }
    }
    return RecurrenceRule(
      freq: freq,
      interval: interval,
      count: count,
      untilUtc: untilUtc,
      untilDate: untilDate,
      byDay: byDay,
      byMonthDay: byMonthDay,
      byMonth: byMonth,
      bySetPos: bySetPos,
      wkst: wkst,
      allDay: allDay,
    );
  }
}
