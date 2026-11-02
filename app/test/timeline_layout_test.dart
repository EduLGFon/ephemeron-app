import 'package:ephemeron/features/calendar/presentation/timeline_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('non-overlapping events each take full width', () {
    final out = layoutDayEvents(const [
      TimelineItem(id: 'a', startMin: 60, endMin: 120),
      TimelineItem(id: 'b', startMin: 180, endMin: 240),
    ]);
    expect(out['a']!.left, 0);
    expect(out['a']!.width, 1);
    expect(out['b']!.left, 0);
    expect(out['b']!.width, 1);
  });

  test('touching edges share full width', () {
    final out = layoutDayEvents(const [
      TimelineItem(id: 'a', startMin: 60, endMin: 120),
      TimelineItem(id: 'b', startMin: 120, endMin: 180),
    ]);
    expect(out['a']!.width, 1);
    expect(out['b']!.width, 1);
  });

  test('equal times split side by side', () {
    final out = layoutDayEvents(const [
      TimelineItem(id: 'a', startMin: 60, endMin: 120),
      TimelineItem(id: 'b', startMin: 60, endMin: 120),
    ]);
    final a = out['a']!;
    final b = out['b']!;
    expect(a.width, moreOrLessEquals(0.5));
    expect(b.width, moreOrLessEquals(0.5));
    expect(a.left + a.width, moreOrLessEquals(b.left));
    expect(a.depth, 0);
    expect(b.depth, 0);
  });

  test('three equal times split in thirds', () {
    final out = layoutDayEvents(const [
      TimelineItem(id: 'a', startMin: 60, endMin: 120),
      TimelineItem(id: 'b', startMin: 60, endMin: 120),
      TimelineItem(id: 'c', startMin: 60, endMin: 120),
    ]);
    expect(out['a']!.width, moreOrLessEquals(1 / 3));
    expect(out['b']!.width, moreOrLessEquals(1 / 3));
    expect(out['c']!.width, moreOrLessEquals(1 / 3));
  });

  test('partial overlap splits side by side', () {
    final out = layoutDayEvents(const [
      TimelineItem(id: 'a', startMin: 60, endMin: 150),
      TimelineItem(id: 'b', startMin: 120, endMin: 210),
    ]);
    expect(out['a']!.width, lessThan(1));
    expect(out['b']!.width, lessThan(1));
    expect(out['a']!.left, isNot(out['b']!.left));
  });

  test('big event contains small one (nesting)', () {
    final out = layoutDayEvents(const [
      TimelineItem(id: 'big', startMin: 60, endMin: 300),
      TimelineItem(id: 'small', startMin: 120, endMin: 240),
    ]);
    final big = out['big']!;
    final small = out['small']!;
    expect(big.width, 1);
    expect(big.depth, 0);
    expect(big.hasChildren, isTrue);
    expect(small.depth, 1);
    expect(small.left, greaterThan(big.left));
    expect(small.left + small.width, lessThanOrEqualTo(1.001));
  });

  test('recursive nesting 4h has 2h has 1h', () {
    final out = layoutDayEvents(const [
      TimelineItem(id: 'h4', startMin: 60, endMin: 300),
      TimelineItem(id: 'h2', startMin: 90, endMin: 210),
      TimelineItem(id: 'h1', startMin: 100, endMin: 160),
    ]);
    expect(out['h4']!.depth, 0);
    expect(out['h2']!.depth, 1);
    expect(out['h1']!.depth, 2);
    expect(out['h1']!.left, greaterThan(out['h2']!.left));
    expect(out['h2']!.left, greaterThan(out['h4']!.left));
  });

  test('contained siblings split inside the parent', () {
    final out = layoutDayEvents(const [
      TimelineItem(id: 'big', startMin: 60, endMin: 400),
      TimelineItem(id: 's1', startMin: 100, endMin: 160),
      TimelineItem(id: 's2', startMin: 120, endMin: 180),
    ]);
    final s1 = out['s1']!;
    final s2 = out['s2']!;
    expect(s1.depth, 1);
    expect(s2.depth, 1);
    expect(s1.left, isNot(s2.left));
    expect(s1.left, greaterThan(out['big']!.left));
  });
}
