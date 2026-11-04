// Smart-filter parsing is defensive: saved JSON can be stale or corrupt.
import 'package:ephemeron/domain/tasks/smart_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invalid or non-object JSON falls back to defaults', () {
    for (final raw in [null, '', 'not json', '[]', '"text"', '{']) {
      final filter = SmartFilter.fromJson(raw);
      expect(filter.dueWindow, SmartDueWindow.any);
      expect(filter.sort, SmartSort.due);
      expect(filter.showCompleted, isFalse);
      expect(filter.listIds, isEmpty);
      expect(filter.tagIds, isEmpty);
      expect(filter.priorities, isEmpty);
      expect(filter.query, '');
    }
  });

  test('unknown keys and wrong types are ignored', () {
    final filter = SmartFilter.fromMap({
      'listIds': <Object?>['l1', 2, '', ' l2 '],
      'tagIds': 'not-a-list',
      'priorities': <Object?>[4, '3', 9, -1, 1],
      'dueWindow': 42,
      'dueFrom': 'not-a-date',
      'dueTo': '2026-02-30',
      'showCompleted': 'yes',
      'query': 7,
      'sort': false,
      'futureKey': {'nested': true},
    });
    expect(filter.listIds, ['l1', 'l2']);
    expect(filter.tagIds, isEmpty);
    expect(filter.priorities, {4, 1});
    expect(filter.dueWindow, SmartDueWindow.any);
    expect(filter.dueFrom, isNull);
    expect(filter.dueTo, isNull);
    expect(filter.showCompleted, isFalse);
    expect(filter.query, '');
    expect(filter.sort, SmartSort.due);
  });

  test('legacy due bounds become a custom window', () {
    final filter = SmartFilter.fromMap({
      'dueFrom': '2026-03-01',
      'dueTo': '2026-03-31',
    });
    expect(filter.dueWindow, SmartDueWindow.custom);
    expect(filter.dueRange(), (from: '2026-03-01', to: '2026-03-31'));
  });

  test('due window presets resolve to inclusive date keys', () {
    final now = DateTime(2026, 3, 15, 12);
    expect(
      const SmartFilter(dueWindow: SmartDueWindow.any).dueRange(now: now),
      (from: null, to: null),
    );
    expect(
      const SmartFilter(dueWindow: SmartDueWindow.today).dueRange(now: now),
      (from: '2026-03-15', to: '2026-03-15'),
    );
    expect(
      const SmartFilter(dueWindow: SmartDueWindow.overdue).dueRange(now: now),
      (from: null, to: '2026-03-14'),
    );
    expect(
      const SmartFilter(dueWindow: SmartDueWindow.next7Days).dueRange(now: now),
      (from: '2026-03-15', to: '2026-03-21'),
    );
    expect(
      const SmartFilter(
        dueWindow: SmartDueWindow.thisMonth,
      ).dueRange(now: DateTime(2026, 2, 10)),
      (from: '2026-02-01', to: '2026-02-28'),
    );
    expect(
      const SmartFilter(
        dueWindow: SmartDueWindow.thisMonth,
      ).dueRange(now: DateTime(2028, 2, 10)),
      (from: '2028-02-01', to: '2028-02-29'),
    );
  });

  test('toMap round-trips supported values only', () {
    const filter = SmartFilter(
      listIds: ['l1'],
      tagIds: ['t1'],
      priorities: {2, 4},
      dueWindow: SmartDueWindow.custom,
      dueFrom: '2026-04-01',
      dueTo: '2026-04-30',
      showCompleted: true,
      query: ' report ',
      sort: SmartSort.priority,
    );
    final encoded = filter.toMap();
    expect(encoded.containsKey('unknown'), isFalse);
    final decoded = SmartFilter.fromMap(encoded);
    expect(decoded.listIds, ['l1']);
    expect(decoded.tagIds, ['t1']);
    expect(decoded.priorities, {2, 4});
    expect(decoded.dueWindow, SmartDueWindow.custom);
    expect(decoded.dueFrom, '2026-04-01');
    expect(decoded.dueTo, '2026-04-30');
    expect(decoded.showCompleted, isTrue);
    expect(decoded.query, 'report');
    expect(decoded.sort, SmartSort.priority);
  });
}
