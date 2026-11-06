part of '../timeline_view.dart';

extension _TimelineViewGrid on _TimelineViewState {
  Widget _buildGrid(
    BuildContext context, {
    required List<OccurrenceCacheData> timed,
    required List<HabitCalendarEntry> timedHabits,
    required DateTime stripAnchor,
    required int stripCount,
  }) {
    final nowController = ref.watch(timelineNowControllerProvider);
    return LayoutBuilder(
      builder: (autoCtx, autoCons) {
        final desired = autoCons.maxHeight > 0
            ? (autoCons.maxHeight / (17 * timelineBaseHourHeight)).clamp(
                timelineMinScale,
                1.0,
              )
            : 1.0;
        if ((desired - autoScale).abs() > 1e-9) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => autoScale = desired);
          });
        }
        return SingleChildScrollView(
          controller: scroll,
          child: SizedBox(
            height: 24 * hourHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TimelineHourGutter(
                  hourHeight: hourHeight,
                  width: timelineGutterWidth,
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (ctx, cons) {
                      final dayWidth = cons.maxWidth / widget.dayCount;
                      final stripWidth = stripCount * dayWidth;
                      lastColW = dayWidth;
                      final placements = timelinePlacementsFor(
                        anchor: stripAnchor,
                        dayCount: stripCount,
                        timed: timed,
                        timedHabits: timedHabits,
                      );
                      final ordered = List<OccurrenceCacheData>.of(timed)
                        ..sort((a, b) {
                          final da = placements[a.id]?.depth ?? 0;
                          final db = placements[b.id]?.depth ?? 0;
                          if (da != db) return da.compareTo(db);
                          return a.startUtc.compareTo(b.startUtc);
                        });
                      return ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          minWidth: stripWidth,
                          maxWidth: stripWidth,
                          child: Transform.translate(
                            offset: Offset(
                              -timelineBufferDays * dayWidth + swipeOffset,
                              0,
                            ),
                            child: SizedBox(
                              width: stripWidth,
                              height: 24 * hourHeight,
                              child: Stack(
                                children: [
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapUp: (d) => tapEmptyAt(
                                      d.localPosition,
                                      dayWidth,
                                      stripAnchor,
                                      stripCount,
                                    ),
                                    child: RepaintBoundary(
                                      child: CustomPaint(
                                        size: Size(stripWidth, 24 * hourHeight),
                                        painter: TimelineGridPainter(
                                          anchor: stripAnchor,
                                          dayCount: stripCount,
                                          hourHeight: hourHeight,
                                          primary: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                  for (final o in ordered)
                                    TimelineEventBlock(
                                      occurrence: o,
                                      anchor: stripAnchor,
                                      dayCount: stripCount,
                                      dayIndex: timelineDayIndex(
                                        stripAnchor,
                                        stripCount,
                                        o.dayKey,
                                      ),
                                      columnWidth: dayWidth,
                                      hourHeight: hourHeight,
                                      placement: placements[o.id],
                                      yOffset: o.eventId == dragId
                                          ? dragDy
                                          : (dragOffset != 0 &&
                                                    o.eventId == pendingMovedId
                                                ? dragOffset
                                                : 0),
                                      leftShift: o.eventId == dragId
                                          ? dragDayDelta * dayWidth
                                          : (pendingMovedId == o.eventId
                                                ? dragXOffset
                                                : 0.0),
                                      onTap: () {
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
                                      onLongPressStart: o.sourceType == 'task'
                                          ? () {}
                                          : () => beginDrag(o.eventId),
                                      onLongPressMoveUpdate: (d) =>
                                          updateDrag(o.eventId, d),
                                      onLongPressEnd: () => endDrag(o.eventId),
                                    ),
                                  for (final h in timedHabits)
                                    HabitTimelineBlock(
                                      key: ValueKey(
                                        'timeline-habit-'
                                        '${h.habitId}-${h.dayKey}',
                                      ),
                                      entry: h,
                                      dayIndex: timelineDayIndex(
                                        stripAnchor,
                                        stripCount,
                                        h.dayKey,
                                      ),
                                      columnWidth: dayWidth,
                                      hourHeight: hourHeight,
                                      placement:
                                          placements[timelineHabitItemId(h)],
                                      onTap: () =>
                                          showHabitActionSheet(context, h),
                                    ),
                                  IgnorePointer(
                                    child: RepaintBoundary(
                                      child: ValueListenableBuilder<DateTime>(
                                        valueListenable: nowController,
                                        builder: (context, now, child) =>
                                            CustomPaint(
                                              size: Size(
                                                stripWidth,
                                                24 * hourHeight,
                                              ),
                                              painter: TimelineNowLinePainter(
                                                anchor: stripAnchor,
                                                dayCount: stripCount,
                                                hourHeight: hourHeight,
                                                now: now,
                                              ),
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ); // SingleChildScrollView return
      }, // builder
    ); // LayoutBuilder
  }
}
