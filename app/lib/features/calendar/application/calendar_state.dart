// Visible calendar window: anchor date, view kind, day count.
// Changing it triggers a cache rebuild (see CalendarScreen).
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CalendarWindow {
  CalendarWindow({required this.anchor, required this.view, this.dayCount = 1});

  final DateTime anchor;
  final CalendarViewKind view;
  final int dayCount;

  DateTime get fromUtc {
    final a = DateTime.utc(anchor.year, anchor.month, anchor.day);
    switch (view) {
      case CalendarViewKind.month:
        final first = DateTime.utc(anchor.year, anchor.month, 1);
        final lead = (first.weekday - DateTime.monday + 7) % 7;
        return first.subtract(Duration(days: lead));
      case CalendarViewKind.multiDay:
      case CalendarViewKind.day:
        return a;
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
        return a.add(Duration(days: dayCount));
      case CalendarViewKind.agenda:
        return a.add(const Duration(days: 90));
      case CalendarViewKind.year:
        return DateTime.utc(anchor.year + 1, 1, 1);
    }
  }
}

enum CalendarViewKind { month, multiDay, day, agenda, year }

class CalendarState extends Notifier<CalendarWindow> {
  @override
  CalendarWindow build() =>
      CalendarWindow(anchor: DateTime.now(), view: CalendarViewKind.month);

  void setView(CalendarViewKind view, {int dayCount = 1}) {
    state = CalendarWindow(
      anchor: state.anchor,
      view: view,
      dayCount: dayCount,
    );
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

  void goToday() {
    state = CalendarWindow(
      anchor: DateTime.now(),
      view: state.view,
      dayCount: state.dayCount,
    );
  }
}
