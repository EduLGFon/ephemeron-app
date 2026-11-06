part of '../timeline_controller.dart';

mixin TimelineDrag on TimelineInteraction {
  void tapEmptyAt(
    Offset pos,
    double colW,
    DateTime stripAnchor,
    int stripCount,
  ) {
    final dayIdx = (pos.dx / colW).floor().clamp(0, stripCount - 1);
    final hour = (pos.dy / hourHeight).floor().clamp(0, 23);
    showEventEditor(
      context,
      initialDay: timelineDayStart(stripAnchor, dayIdx),
      initialHour: hour,
    );
  }

  void beginDrag(String eventId) {
    setState(() {
      dragId = eventId;
      dragDy = 0;
      dragDayDelta = 0;
    });
  }

  void updateDrag(String eventId, LongPressMoveUpdateDetails d) {
    if (dragId != eventId) return;
    final dayDelta = (d.offsetFromOrigin.dx / lastColW).round();
    final snap =
        (d.offsetFromOrigin.dy / hourHeight * 60 / 15).round() *
        15 /
        60 *
        hourHeight;
    setState(() {
      dragDy = snap;
      dragDayDelta = dayDelta;
    });
  }

  void endDrag(String eventId) {
    if (dragId == eventId) {
      unawaited(_dragEnd());
    }
  }

  void _clearPending() {
    if (!mounted) return;
    setState(() {
      dragOffset = 0;
      dragXOffset = 0;
      pendingMovedId = null;
    });
  }

  Future<void> _dragEnd() async {
    final id = dragId;
    final dy = dragDy;
    final dayDelta = dragDayDelta;
    setState(() {
      dragId = null;
      dragDy = 0;
      dragDayDelta = 0;
      pendingMovedId = id;
      dragOffset = dy;
      dragXOffset = dayDelta * lastColW;
    });
    if (id == null) return;
    final snapMin = (dy / hourHeight * 60).round();
    final snapped = (snapMin / 15).round() * 15;
    if (snapped == 0 && dayDelta == 0) {
      _clearPending();
      return;
    }
    final repo = ref.read(eventRepositoryProvider);
    final master = await (repo.dbSelect()..where((e) => e.id.equals(id)))
        .getSingleOrNull();
    if (master == null || !context.mounted) {
      _clearPending();
      return;
    }
    if (master.isAllDay || master.startUtc == null) {
      _clearPending();
      return;
    }
    final orig = DateTime.fromMillisecondsSinceEpoch(
      master.startUtc!,
      isUtc: true,
    );
    final newStart = orig
        .add(Duration(minutes: snapped))
        .add(Duration(days: dayDelta));
    final newEnd = DateTime.fromMillisecondsSinceEpoch(
      master.endUtc ?? master.startUtc!,
      isUtc: true,
    ).add(Duration(minutes: snapped)).add(Duration(days: dayDelta));
    if (master.rrule != null && master.rrule!.isNotEmpty) {
      final scope = await showScopeSheet(context);
      if (scope == null || !context.mounted) {
        _clearPending();
        return;
      }
      await repo.editOccurrence(
        id,
        orig,
        scope: scope,
        startUtc: newStart,
        endUtc: newEnd,
      );
    } else {
      await repo.editOccurrence(
        id,
        orig,
        scope: EditScope.all,
        startUtc: newStart,
        endUtc: newEnd,
      );
    }
    if (context.mounted) {
      try {
        final range = ref.read(calendarCacheRangeProvider);
        await ref
            .read(occurrenceRepositoryProvider)
            .rebuildWindow(
              windowStartUtc: range.fromUtc,
              windowEndUtc: range.toUtc,
            );
      } catch (_) {}
      if (context.mounted) {
        setState(() {
          dragOffset = 0;
          pendingMovedId = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Event moved')));
      }
    }
  }
}
