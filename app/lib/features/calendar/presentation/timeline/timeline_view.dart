// N-day / day timeline: hour gutter, day headers, all-day strip,
// current-time line, tap-empty to create, tap event for details.
// Composes the chrome, painters, event blocks, and interaction mixin;
// overlap layout lives in timeline_layout.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/drift/app_database.dart';
import '../../application/calendar_providers.dart';
import '../event_details_sheet.dart';
import 'timeline_chrome.dart';
import 'timeline_controller.dart';
import 'timeline_event_block.dart';
import 'timeline_painters.dart';
import 'timeline_utils.dart';

class TimelineView extends ConsumerStatefulWidget {
  const TimelineView({super.key, required this.anchor, required this.dayCount});

  final DateTime anchor;
  final int dayCount;

  @override
  ConsumerState<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends ConsumerState<TimelineView>
    with TimelineInteraction, SingleTickerProviderStateMixin {
  @override
  DateTime get anchor => widget.anchor;

  @override
  int get dayCount => widget.dayCount;

  @override
  void initState() {
    super.initState();
    initTimelineInteraction();
  }

  @override
  void didUpdateWidget(TimelineView old) {
    super.didUpdateWidget(old);
    if (old.anchor != widget.anchor || old.dayCount != widget.dayCount) {
      refreshTimelineWindow();
    }
  }

  @override
  void dispose() {
    disposeTimelineInteraction();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final window = ref.watch(calendarStateProvider);
    final occAsync = ref.watch(windowOccurrencesProvider(window));
    final occs = occAsync.maybeWhen(
      data: (v) => v,
      orElse: () => const <OccurrenceCacheData>[],
    );
    final timed = <OccurrenceCacheData>[];
    final allDay = <OccurrenceCacheData>[];
    for (final o in occs) {
      if (!timelineIsVisibleDay(widget.anchor, widget.dayCount, o.dayKey)) {
        continue;
      }
      if (timelineIsAllDay(o)) {
        allDay.add(o);
      } else {
        timed.add(o);
      }
    }

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
              ),
              if (allDay.isNotEmpty)
                TimelineAllDayStrip(
                  occs: allDay,
                  anchor: widget.anchor,
                  dayCount: widget.dayCount,
                  gutterWidth: timelineGutterWidth,
                  swipeOffset: swipeOffset,
                  onTap: (id) => showEventDetails(context, id),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (autoCtx, autoCons) {
                    final desired = autoCons.maxHeight > 0
                        ? (autoCons.maxHeight / (17 * timelineBaseHourHeight))
                              .clamp(timelineMinScale, 1.0)
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
                                  final colW = cons.maxWidth / widget.dayCount;
                                  lastColW = colW;
                                  final placements = timelinePlacementsFor(
                                    anchor: widget.anchor,
                                    dayCount: widget.dayCount,
                                    timed: timed,
                                  );
                                  final ordered =
                                      List<OccurrenceCacheData>.of(
                                        timed,
                                      )..sort((a, b) {
                                        final da = placements[a.id]?.depth ?? 0;
                                        final db = placements[b.id]?.depth ?? 0;
                                        if (da != db) return da.compareTo(db);
                                        return a.startUtc.compareTo(b.startUtc);
                                      });
                                  return Transform.translate(
                                    offset: Offset(swipeOffset, 0),
                                    child: Stack(
                                      children: [
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTapUp: (d) =>
                                              tapEmptyAt(d.localPosition, colW),
                                          child: RepaintBoundary(
                                            child: CustomPaint(
                                              size: Size(
                                                cons.maxWidth,
                                                24 * hourHeight,
                                              ),
                                              painter: TimelineGridPainter(
                                                anchor: widget.anchor,
                                                dayCount: widget.dayCount,
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
                                            anchor: widget.anchor,
                                            dayCount: widget.dayCount,
                                            dayIndex: timelineDayIndex(
                                              widget.anchor,
                                              widget.dayCount,
                                              o.dayKey,
                                            ),
                                            columnWidth: colW,
                                            hourHeight: hourHeight,
                                            placement: placements[o.id],
                                            yOffset: o.eventId == dragId
                                                ? dragDy
                                                : (dragOffset != 0 &&
                                                          o.eventId ==
                                                              pendingMovedId
                                                      ? dragOffset
                                                      : 0),
                                            leftShift: o.eventId == dragId
                                                ? dragDayDelta * colW
                                                : (pendingMovedId == o.eventId
                                                      ? dragXOffset
                                                      : 0.0),
                                            onTap: () => showEventDetails(
                                              context,
                                              o.eventId,
                                            ),
                                            onLongPressStart: () =>
                                                beginDrag(o.eventId),
                                            onLongPressMoveUpdate: (d) =>
                                                updateDrag(o.eventId, d),
                                            onLongPressEnd: () =>
                                                endDrag(o.eventId),
                                          ),
                                        IgnorePointer(
                                          child: RepaintBoundary(
                                            child: CustomPaint(
                                              size: Size(
                                                cons.maxWidth,
                                                24 * hourHeight,
                                              ),
                                              painter: TimelineNowLinePainter(
                                                anchor: widget.anchor,
                                                dayCount: widget.dayCount,
                                                hourHeight: hourHeight,
                                                now: DateTime.now(),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
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
                ), // LayoutBuilder
              ), // Expanded outer
            ],
          ), // Column
        ), // GestureDetector
      ), // Listener
    ); // Focus
  }
}
