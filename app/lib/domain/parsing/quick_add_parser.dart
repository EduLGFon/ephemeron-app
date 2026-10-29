// Quick-add shorthand parser. Pure Dart.
// Shorthands: #tag, ~list, -p1..-p4. Remainder goes through natural parsing.
import 'natural_date_parser.dart';

class QuickAddParsed {
  QuickAddParsed({
    required this.title,
    required this.tags,
    this.list,
    this.priority = 0,
    this.due,
    this.rrule,
  });

  final String title;
  final List<String> tags;
  final String? list;
  final int priority;
  final DateTime? due;
  final String? rrule;
}

QuickAddParsed parseQuickAdd(String input, {DateTime? now}) {
  var working = ' $input ';
  final tags = <String>[];
  for (final m in RegExp(r'#([\p{L}\p{N}_-]+)', unicode: true)
      .allMatches(working)) {
    tags.add(m.group(1)!.toLowerCase());
  }
  working = working.replaceAll(
      RegExp(r'#([\p{L}\p{N}_-]+)', unicode: true), ' ');

  String? list;
  final listM = RegExp(r'~([\p{L}\p{N}_-]+)', unicode: true).firstMatch(working);
  if (listM != null) {
    list = listM.group(1)!;
    working = working.replaceFirst(listM.group(0)!, ' ');
  }

  var priority = 0;
  final priM = RegExp(r'-p([1-4])').firstMatch(working);
  if (priM != null) {
    // -p1 is highest urgency -> priority 4 .. -p4 -> priority 1.
    priority = 5 - int.parse(priM.group(1)!);
    working = working.replaceFirst(priM.group(0)!, ' ');
  }

  final natural = parseNatural(working, now: now);
  return QuickAddParsed(
    title: natural.title,
    tags: tags,
    list: list,
    priority: priority,
    due: natural.due,
    rrule: natural.rrule,
  );
}
