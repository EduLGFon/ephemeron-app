// Interaction state for the timeline: scroll position, zoom, pinch,
// tap-empty-to-create, and long-press drag-to-move with 15-minute snapping.
// Mixed into the timeline view's state; the state supplies [anchor] and
// [dayCount] from its widget.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/event_repository.dart';
import '../../application/calendar_providers.dart';
import '../event_editor_sheet.dart';
import '../scope_sheet.dart';
import 'timeline_utils.dart';

const double timelineBaseHourHeight = 56;
const double timelineGutterWidth = 48;
const double timelineMinScale = 0.5;
const double timelineMaxScale = 3.0;

mixin TimelineInteraction {
  DateTime get anchor;
  int get dayCount;
  WidgetRef get ref;
  BuildContext get context;
  bool get mounted;
  void setState(VoidCallback fn);

  final ScrollController scroll = ScrollController();
  String? dragId;
  double dragDy = 0;
  int dragDayDelta = 0;
  double dragOffset = 0;
  double dragXOffset = 0;
  double lastColW = 1;
  String? pendingMovedId;
  bool didJump = false;
  double scale = 1;
  // Auto-fitted base scale so the 6h-23h window (17 hours) fits the
  // available viewport. Manual zoom ([scale]) multiplies on top.
  double autoScale = 1;
  // Active pointers for pinch tracking. Listener-based so pinch never
  // competes with scrolling, tapping, or event dragging in the arena.
  final Map<int, Offset> pointers = {};
  double? pinchStartDist;
  double pinchBaseScale = 1;

  // Horizontal swipe state for advancing one day at a time while keeping
  // the hour gutter fixed.
  double swipeOffset = 0;
  bool swipeDragging = false;
  bool swipeDisabled = false;
  Animation<double>? swipeAnimation;
  int _swipeGeneration = 0;
  late AnimationController swipeController;

  double get hourHeight => timelineBaseHourHeight * autoScale * scale;
  void initTimelineInteraction() {
    swipeController =
        AnimationController(
          vsync: this as TickerProvider,
          duration: const Duration(milliseconds: 180),
        )..addListener(() {
          final animation = swipeAnimation;
          if (animation != null) {
            setState(() => swipeOffset = animation.value);
          }
        });
    WidgetsBinding.instance.addPostFrameCallback((_) => maybeJump());
  }

  void refreshTimelineWindow() {
    // Keep the current vertical position when the visible day changes; only
    // the initial mount auto-scrolls to now (or 8am when today is off-screen).
    dragId = null;
    dragDy = 0;
  }

  void disposeTimelineInteraction() {
    swipeController.dispose();
    scroll.dispose();
  }

  void _swipeAbort() {
    _swipeGeneration++;
    swipeController.stop();
    swipeAnimation = null;
    swipeDragging = false;
    if (swipeOffset != 0) setState(() => swipeOffset = 0);
  }

  void onSwipeStart(DragStartDetails details) {
    if (swipeController.isAnimating) _swipeAbort();
    if (dragId != null) {
      swipeDragging = false;
      return;
    }
    if (pointers.length > 1) {
      swipeDisabled = true;
      swipeDragging = false;
      return;
    }
    swipeDisabled = false;
    swipeDragging = true;
    swipeOffset = 0;
    swipeAnimation = null;
  }

  void onSwipeUpdate(DragUpdateDetails details) {
    if (!swipeDragging || swipeDisabled || dragId != null) return;
    final step = lastColW.clamp(1.0, double.infinity);
    final limit = step * timelineBufferDays;
    swipeOffset = (swipeOffset + details.delta.dx).clamp(-limit, limit);
    setState(() {});
  }

  Future<void> onSwipeEnd(DragEndDetails details) async {
    if (!swipeDragging) {
      swipeDragging = false;
      return;
    }
    swipeDragging = false;
    if (swipeDisabled || dragId != null) {
      await _swipeSnapBack();
      return;
    }
    final step = lastColW.clamp(1.0, double.infinity);
    final velocity = details.primaryVelocity ?? 0;
    // Project the drag with a short fling carry, then snap to whole days.
    // A single gesture may cross several days; it is not capped at one.
    final projected = swipeOffset + velocity * 0.12;
    var days = (-projected / step).round();
    days = days.clamp(-timelineBufferDays, timelineBufferDays);
    if (days == 0) {
      await _swipeSnapBack();
      return;
    }
    await _swipeReverse(days, step);
  }

  void onSwipeCancel() {
    swipeDragging = false;
    if (swipeOffset != 0) _swipeSnapBack();
  }

  Future<void> _swipeReverse(int days, double step) async {
    final generation = ++_swipeGeneration;
    swipeController.duration = Duration(
      milliseconds: (180 + (days.abs() - 1) * 45).clamp(180, 600),
    );
    // The buffered days are already rendered, so slide by the snapped day
    // count and move the anchor in the same frame. The visible pixels do not
    // change, and a gesture may span several days.
    await _swipeAnimateTo(-days * step);
    if (!mounted || generation != _swipeGeneration) return;
    ref.read(calendarStateProvider.notifier).shift(days);
    setState(() => swipeOffset = 0);
  }

  Future<void> _swipeSnapBack() async {
    final generation = ++_swipeGeneration;
    swipeController.duration = const Duration(milliseconds: 180);
    await _swipeAnimateTo(0);
    if (!mounted || generation != _swipeGeneration) return;
  }

  Future<void> _swipeAnimateTo(double target) async {
    final begin = swipeOffset;
    if ((begin - target).abs() < 0.5) {
      if (mounted) setState(() => swipeOffset = target);
      return;
    }
    swipeAnimation = Tween<double>(begin: begin, end: target).animate(
      CurvedAnimation(parent: swipeController, curve: Curves.easeOutCubic),
    );
    swipeController.reset();
    try {
      await swipeController.forward().orCancel;
    } on TickerCanceled {
      return;
    }
  }

  void maybeJump() {
    if (didJump || !scroll.hasClients) return;
    didJump = true;
    final now = DateTime.now();
    final todayIdx = _todayIndex(now);
    // Scroll to current time when today is visible, else to 8am.
    final hour = todayIdx >= 0 ? now.hour + now.minute / 60.0 : 8.0;
    final y = (hour - 1).clamp(0.0, 23.0) * hourHeight;
    scroll.jumpTo(y.clamp(0.0, scroll.position.maxScrollExtent));
  }

  int _todayIndex(DateTime now) {
    for (var i = 0; i < dayCount; i++) {
      final d = timelineDayStart(anchor, i);
      if (d.year == now.year && d.month == now.month && d.day == now.day) {
        return i;
      }
    }
    return -1;
  }

  void applyScale(double next) {
    next = next.clamp(timelineMinScale, timelineMaxScale);
    if (next == scale) return;
    final ratio = next / scale;
    final offset = scroll.hasClients ? scroll.offset : 0.0;
    setState(() => scale = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      scroll.jumpTo(
        (offset * ratio).clamp(0.0, scroll.position.maxScrollExtent),
      );
    });
  }

  KeyEventResult onTimelineKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!HardwareKeyboard.instance.isControlPressed) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.equal:
      case LogicalKeyboardKey.add:
      case LogicalKeyboardKey.numpadAdd:
        applyScale(scale * 1.25);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.minus:
      case LogicalKeyboardKey.numpadSubtract:
        applyScale(scale / 1.25);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.digit0:
      case LogicalKeyboardKey.numpad0:
        applyScale(1);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  double _pointerDist() {
    final pts = pointers.values.toList();
    return (pts[0] - pts[1]).distance;
  }

  void onTimelinePointerDown(PointerDownEvent e) {
    pointers[e.pointer] = e.position;
    if (pointers.length == 2) {
      pinchStartDist = _pointerDist();
      pinchBaseScale = scale;
      swipeDisabled = true;
      _swipeAbort();
    }
  }

  void onTimelinePointerMove(PointerMoveEvent e) {
    if (!pointers.containsKey(e.pointer)) return;
    pointers[e.pointer] = e.position;
    if (pointers.length == 2 && pinchStartDist != null && pinchStartDist! > 0) {
      applyScale(pinchBaseScale * _pointerDist() / pinchStartDist!);
    }
  }

  void onTimelinePointerEnd(PointerEvent e) {
    pointers.remove(e.pointer);
    if (pointers.length < 2) pinchStartDist = null;
    if (pointers.isEmpty) swipeDisabled = false;
  }

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
      // Rebuild occurrence cache so the moved event reappears immediately.
      try {
        final range = ref.read(calendarCacheRangeProvider);
        await ref
            .read(occurrenceRepositoryProvider)
            .rebuildWindow(
              windowStartUtc: range.fromUtc,
              windowEndUtc: range.toUtc,
            );
      } catch (_) {
        // Best-effort; next navigation rebuilds.
      }
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
