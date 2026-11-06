part of '../timeline_view.dart';

extension _TimelineViewBuild on _TimelineViewState {
  Widget _buildTimeline(BuildContext context) {
    final range = ref.watch(calendarCacheRangeProvider);
    final occAsync = ref.watch(windowOccurrencesProvider(range));
    final building = ref.watch(calendarCacheBuildingProvider);
    // Keep the previous day rows while the shifted window reloads. The old
    // buffer already covers the days that slide in, so no empty frame shows.
    final occs = occAsync.maybeWhen(
      data: (v) {
        _lastOccurrences = v;
        return v;
      },
      orElse: () => _lastOccurrences,
    );
    final habitEntries = ref
        .watch(calendarHabitEntriesProvider)
        .maybeWhen(data: (v) => v, orElse: () => const <HabitCalendarEntry>[]);
    final stripAnchor = timelineStripAnchor(widget.anchor);
    final stripCount = timelineStripCount(widget.dayCount);
    final timed = <OccurrenceCacheData>[];
    final allDay = <OccurrenceCacheData>[];
    for (final o in occs) {
      if (!timelineIsVisibleDay(stripAnchor, stripCount, o.dayKey)) {
        continue;
      }
      if (timelineIsAllDay(o)) {
        allDay.add(o);
      } else {
        timed.add(o);
      }
    }
    final timedHabits = <HabitCalendarEntry>[];
    final allDayHabits = <HabitCalendarEntry>[];
    for (final h in habitEntries) {
      if (!timelineIsVisibleDay(stripAnchor, stripCount, h.dayKey)) continue;
      if (h.isTimed) {
        timedHabits.add(h);
      } else {
        allDayHabits.add(h);
      }
    }
    timedHabits.sort((a, b) {
      final byTime = a.timeMinutes!.compareTo(b.timeMinutes!);
      if (byTime != 0) return byTime;
      final byName = a.habitName.compareTo(b.habitName);
      if (byName != 0) return byName;
      return a.habitId.compareTo(b.habitId);
    });

    return Focus(
      autofocus: true,
      onKeyEvent: onTimelineKeyEvent,
      child: Listener(
        onPointerDown: onTimelinePointerDown,
        onPointerMove: onTimelinePointerMove,
        onPointerUp: onTimelinePointerEnd,
        onPointerCancel: onTimelinePointerEnd,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: onSwipeStart,
          onHorizontalDragUpdate: onSwipeUpdate,
          onHorizontalDragEnd: onSwipeEnd,
          onHorizontalDragCancel: onSwipeCancel,
          child: Column(
            children: [
              TimelineDayHeader(
                anchor: widget.anchor,
                dayCount: widget.dayCount,
                gutterWidth: timelineGutterWidth,
                swipeOffset: swipeOffset,
                onDayTap: widget.dayCount == 7
                    ? (day) {
                        final notifier = ref.read(
                          calendarStateProvider.notifier,
                        );
                        notifier.setView(CalendarViewKind.day);
                        notifier.goTo(day);
                      }
                    : null,
              ),
              if (timed.isEmpty &&
                  allDay.isEmpty &&
                  timedHabits.isEmpty &&
                  allDayHabits.isEmpty &&
                  building)
                const LinearProgressIndicator(minHeight: 2),
              if (allDay.isNotEmpty || allDayHabits.isNotEmpty)
                TimelineAllDayStrip(
                  occs: allDay,
                  habits: allDayHabits,
                  anchor: widget.anchor,
                  dayCount: widget.dayCount,
                  gutterWidth: timelineGutterWidth,
                  swipeOffset: swipeOffset,
                  onTap: (o) {
                    if (o.sourceType == 'task') {
                      showTaskActionSheet(
                        context,
                        taskId: o.eventId,
                        occurrenceDate: o.dayKey,
                      );
                    } else {
                      showEventDetails(context, o.eventId);
                    }
                  },
                ),
              Expanded(
                child: _buildGrid(
                  context,
                  timed: timed,
                  timedHabits: timedHabits,
                  stripAnchor: stripAnchor,
                  stripCount: stripCount,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
