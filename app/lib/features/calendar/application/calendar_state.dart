// Visible calendar window: anchor date, view kind, day count.
// Changing it may trigger a cache rebuild (see CalendarScreen).
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Extra days materialized on each side of day and multi-day windows so a
/// swipe can reveal multiple adjacent days before the anchor moves.
const int calendarDayBufferDays = 14;

/// Half-open UTC range of occurrence cache rows.
///
/// Used as the stable key for occurrence streams so navigation within an
/// already materialized range does not resubscribe or reload.
class CalendarRange {
  CalendarRange({required DateTime fromUtc, required DateTime toUtc})
    : fromUtc = _utcMs(fromUtc),
      toUtc = _utcMs(toUtc);

  final DateTime fromUtc;
  final DateTime toUtc;

  static DateTime _utcMs(DateTime value) => DateTime.fromMillisecondsSinceEpoch(
    value.toUtc().millisecondsSinceEpoch,
    isUtc: true,
  );

  bool covers(CalendarRange other) =>
      !fromUtc.isAfter(other.fromUtc) && !toUtc.isBefore(other.toUtc);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalendarRange &&
          other.fromUtc == fromUtc &&
          other.toUtc == toUtc;

  @override
  int get hashCode => Object.hash(fromUtc, toUtc);

  @override
  String toString() => 'CalendarRange($fromUtc, $toUtc)';
}

class CalendarWindow {
  CalendarWindow({required this.anchor, required this.view, this.dayCount = 1});

  final DateTime anchor;
  final CalendarViewKind view;
  final int dayCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalendarWindow &&
          other.anchor == anchor &&
          other.view == view &&
          other.dayCount == dayCount;

  @override
  int get hashCode => Object.hash(anchor, view, dayCount);

  DateTime get fromUtc {
    final a = DateTime.utc(anchor.year, anchor.month, anchor.day);
    switch (view) {
      case CalendarViewKind.month:
        final first = DateTime.utc(anchor.year, anchor.month, 1);
        final lead = (first.weekday - DateTime.monday + 7) % 7;
        return first.subtract(Duration(days: lead));
      case CalendarViewKind.multiDay:
      case CalendarViewKind.day:
        // Include buffer days each side for the swipe transition.
        return a.subtract(const Duration(days: calendarDayBufferDays));
      case CalendarViewKind.agenda:
        return a.subtract(const Duration(days: 30));
      case CalendarViewKind.year:
        return DateTime.utc(anchor.year, 1, 1);
    }
  }

  DateTime get toUtc {
    final a = DateTime.utc(anchor.year, anchor.month, anchor.day);
    switch (view) {
      case CalendarViewKind.month:
        final first = DateTime.utc(anchor.year, anchor.month, 1);
        final lead = (first.weekday - DateTime.monday + 7) % 7;
        return first
            .subtract(Duration(days: lead))
            .add(const Duration(days: 42));
      case CalendarViewKind.multiDay:
      case CalendarViewKind.day:
        return a.add(Duration(days: dayCount + calendarDayBufferDays));
      case CalendarViewKind.agenda:
        return a.add(const Duration(days: 90));
      case CalendarViewKind.year:
        return DateTime.utc(anchor.year + 1, 1, 1);
    }
  }

  /// Range materialized in the occurrence cache.
  CalendarRange get cacheRange => CalendarRange(fromUtc: fromUtc, toUtc: toUtc);

  /// Range actually visible to the user, without swipe buffer days.
  CalendarRange get visibleRange {
    final a = DateTime.utc(anchor.year, anchor.month, anchor.day);
    switch (view) {
      case CalendarViewKind.month:
      case CalendarViewKind.agenda:
      case CalendarViewKind.year:
        return cacheRange;
      case CalendarViewKind.multiDay:
      case CalendarViewKind.day:
        return CalendarRange(
          fromUtc: a,
          toUtc: a.add(Duration(days: dayCount)),
        );
    }
  }
}

enum CalendarViewKind { month, multiDay, day, agenda, year }

class CalendarState extends Notifier<CalendarWindow> {
  @override
  CalendarWindow build() =>
      CalendarWindow(anchor: DateTime.now(), view: CalendarViewKind.month);

  void restore(CalendarViewKind view, DateTime anchor, {int dayCount = 1}) {
    state = CalendarWindow(anchor: anchor, view: view, dayCount: dayCount);
  }

  void setView(CalendarViewKind view, {int dayCount = 1}) {
    // Opening the month view always starts from today; other views keep
    // the current anchor so swipes and selections survive view switches.
    final anchor = view == CalendarViewKind.month
        ? DateTime.now()
        : state.anchor;
    state = CalendarWindow(anchor: anchor, view: view, dayCount: dayCount);
  }

  void goTo(DateTime anchor) {
    state = CalendarWindow(
      anchor: anchor,
      view: state.view,
      dayCount: state.dayCount,
    );
  }

  void shift(int days) {
    state = CalendarWindow(
      anchor: state.anchor.add(Duration(days: days)),
      view: state.view,
      dayCount: state.dayCount,
    );
  }

  /// Moves to the same day in another month, clamped to that month's length.
  void shiftMonths(int months) {
    final anchor = state.anchor;
    final first = DateTime(anchor.year, anchor.month + months, 1);
    final lastDay = DateTime(first.year, first.month + 1, 0).day;
    state = CalendarWindow(
      anchor: DateTime(first.year, first.month, math.min(anchor.day, lastDay)),
      view: state.view,
      dayCount: state.dayCount,
    );
  }

  void goToday() {
    state = CalendarWindow(
      anchor: DateTime.now(),
      view: state.view,
      dayCount: state.dayCount,
    );
  }
}
