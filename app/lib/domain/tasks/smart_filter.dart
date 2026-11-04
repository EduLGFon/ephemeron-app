// Defensive smart-list filter model. Saved filters are user-editable JSON
// from older app versions or backups, so unknown keys and wrong types are
// ignored instead of throwing. Due windows turn relative presets into
// YYYY-MM-DD bounds at query time.
library;

import 'dart:convert';

import '../../core/time/time.dart';

enum SmartDueWindow { any, today, overdue, next7Days, thisMonth, custom }

extension SmartDueWindowLabel on SmartDueWindow {
  String get label => switch (this) {
    SmartDueWindow.any => 'Any due date',
    SmartDueWindow.today => 'Today',
    SmartDueWindow.overdue => 'Overdue',
    SmartDueWindow.next7Days => 'Next 7 days',
    SmartDueWindow.thisMonth => 'This month',
    SmartDueWindow.custom => 'Custom dates',
  };

  static SmartDueWindow parse(Object? value) {
    if (value is! String) return SmartDueWindow.any;
    for (final window in SmartDueWindow.values) {
      if (window.name == value) return window;
    }
    return SmartDueWindow.any;
  }
}

enum SmartSort { due, priority, created, title }

extension SmartSortLabel on SmartSort {
  String get label => switch (this) {
    SmartSort.due => 'Due date',
    SmartSort.priority => 'Priority',
    SmartSort.created => 'Newest',
    SmartSort.title => 'Title',
  };

  static SmartSort parse(Object? value) {
    if (value is! String) return SmartSort.due;
    for (final sort in SmartSort.values) {
      if (sort.name == value) return sort;
    }
    return SmartSort.due;
  }
}

class SmartFilter {
  const SmartFilter({
    this.listIds = const [],
    this.tagIds = const [],
    this.priorities = const {},
    this.dueWindow = SmartDueWindow.any,
    this.dueFrom,
    this.dueTo,
    this.showCompleted = false,
    this.query = '',
    this.sort = SmartSort.due,
  });

  final List<String> listIds;
  final List<String> tagIds;
  final Set<int> priorities;
  final SmartDueWindow dueWindow;
  final String? dueFrom; // YYYY-MM-DD, custom windows only
  final String? dueTo; // YYYY-MM-DD, custom windows only
  final bool showCompleted;
  final String query;
  final SmartSort sort;

  /// Parses a filter map from saved JSON or an in-memory caller. Never throws.
  factory SmartFilter.fromMap(Map<String, Object?> map) {
    final dueFrom = _dateKey(map['dueFrom']);
    final dueTo = _dateKey(map['dueTo']);
    var dueWindow = SmartDueWindowLabel.parse(map['dueWindow']);
    if (dueWindow == SmartDueWindow.any &&
        map['dueWindow'] is! String &&
        (dueFrom != null || dueTo != null)) {
      // Legacy filters stored only explicit bounds.
      dueWindow = SmartDueWindow.custom;
    }
    final query = map['query'];
    return SmartFilter(
      listIds: _stringList(map['listIds']),
      tagIds: _stringList(map['tagIds']),
      priorities: _prioritySet(map['priorities']),
      dueWindow: dueWindow,
      dueFrom: dueFrom,
      dueTo: dueTo,
      showCompleted: map['showCompleted'] == true,
      query: query is String ? query.trim() : '',
      sort: SmartSortLabel.parse(map['sort']),
    );
  }

  /// Decodes filterJson. Invalid JSON or a non-object payload yields defaults.
  factory SmartFilter.fromJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const SmartFilter();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const SmartFilter();
      return SmartFilter.fromMap(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } catch (_) {
      return const SmartFilter();
    }
  }

  Map<String, Object?> toMap() {
    return {
      if (listIds.isNotEmpty) 'listIds': listIds,
      if (tagIds.isNotEmpty) 'tagIds': tagIds,
      if (priorities.isNotEmpty)
        'priorities': priorities.toList()..sort((a, b) => b.compareTo(a)),
      'dueWindow': dueWindow.name,
      if (dueFrom != null) 'dueFrom': dueFrom,
      if (dueTo != null) 'dueTo': dueTo,
      'showCompleted': showCompleted,
      if (query.trim().isNotEmpty) 'query': query.trim(),
      'sort': sort.name,
    };
  }

  /// Inclusive date bounds for the selected due window. Null means unbounded.
  ({String? from, String? to}) dueRange({DateTime? now}) {
    final local = now ?? DateTime.now();
    final today = DateTime(local.year, local.month, local.day);
    switch (dueWindow) {
      case SmartDueWindow.any:
        return (from: null, to: null);
      case SmartDueWindow.today:
        final key = dateKey(today);
        return (from: key, to: key);
      case SmartDueWindow.overdue:
        return (
          from: null,
          to: dateKey(today.subtract(const Duration(days: 1))),
        );
      case SmartDueWindow.next7Days:
        return (
          from: dateKey(today),
          to: dateKey(today.add(const Duration(days: 6))),
        );
      case SmartDueWindow.thisMonth:
        return (
          from: dateKey(DateTime(today.year, today.month, 1)),
          to: dateKey(DateTime(today.year, today.month + 1, 0)),
        );
      case SmartDueWindow.custom:
        return (from: dueFrom, to: dueTo);
    }
  }
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  final result = <String>[];
  for (final item in value) {
    if (item is String) {
      final trimmed = item.trim();
      if (trimmed.isNotEmpty) result.add(trimmed);
    }
  }
  return List.unmodifiable(result);
}

Set<int> _prioritySet(Object? value) {
  if (value is! List) return const {};
  final result = <int>{};
  for (final item in value) {
    if (item is int && item >= 0 && item <= 4) result.add(item);
  }
  return Set.unmodifiable(result);
}

String? _dateKey(Object? value) {
  if (value is! String) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return value;
}
