// N-day / day timeline: hour gutter, day headers, all-day strip,
// current-time line, tap-empty to create, tap event for details,
// vertical drag on an event to move it with 15-minute snapping
// (scope-asked for recurring), pinch and Ctrl+= / Ctrl+- zoom.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/time.dart';
import '../../../data/drift/app_database.dart';
import '../../../data/repositories/event_repository.dart';
import '../application/calendar_providers.dart';
import 'event_details_sheet.dart';
import 'event_editor_sheet.dart';
import 'scope_sheet.dart';

class TimelineView extends ConsumerStatefulWidget {
  const TimelineView({super.key, required this.anchor, required this.dayCount});

  final DateTime anchor;
  final int dayCount;

  @override
  ConsumerState<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends ConsumerState<TimelineView> {
  static const double baseHourHeight = 56;
  static const double gutterWidth = 48;
  static const double minScale = 0.5;
  static const double maxScale = 3.0;

  late final ScrollController _scroll;
  String? _dragId;
  double _dragDy = 0;
  int _dragDayDelta = 0;
  double _dragOffset = 0;
  double _dragXOffset = 0;
  double _lastColW = 1;
  String? _pendingMovedId;
  bool _didJump = false;
  double _scale = 1;

  // Active pointers for pinch tracking. Listener-based so pinch never
  // competes with scrolling, tapping, or event dragging in the arena.
  final Map<int, Offset> _pointers = {};
  double? _pinchStartDist;
  double _pinchBaseScale = 1;

  double get hourHeight => baseHourHeight * _scale;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeJump());
  }

  @override
  void didUpdateWidget(TimelineView old) {
    super.didUpdateWidget(old);
    if (old.anchor != widget.anchor || old.dayCount != widget.dayCount) {
      _didJump = false;
      _dragId = null;
      _dragDy = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeJump());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  DateTime _dayStart(int i) {
    final a = widget.anchor;
    return DateTime(a.year, a.month, a.day).add(Duration(days: i));
  }

  void _maybeJump() {
    if (_didJump || !_scroll.hasClients) return;
    _didJump = true;
    final now = DateTime.now();
    final todayIdx = _todayIndex(now);
    // Scroll to current time when today is visible, else to 8am.
    final hour = todayIdx >= 0 ? now.hour + now.minute / 60.0 : 8.0;
    final y = (hour - 1).clamp(0.0, 23.0) * hourHeight;
    _scroll.jumpTo(y.clamp(0.0, _scroll.position.maxScrollExtent));
  }

  int _todayIndex(DateTime now) {
    for (var i = 0; i < widget.dayCount; i++) {
      final d = _dayStart(i);
      if (d.year == now.year && d.month == now.month && d.day == now.day) {
        return i;
      }
    }
    return -1;
  }

  void _applyScale(double next) {
    next = next.clamp(minScale, maxScale);
    if (next == _scale) return;
    final ratio = next / _scale;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    setState(() => _scale = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(
        (offset * ratio).clamp(0.0, _scroll.position.maxScrollExtent),
      );
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!HardwareKeyboard.instance.isControlPressed) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.equal:
      case LogicalKeyboardKey.add:
      case LogicalKeyboardKey.numpadAdd:
        _applyScale(_scale * 1.25);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.minus:
      case LogicalKeyboardKey.numpadSubtract:
        _applyScale(_scale / 1.25);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.digit0:
      case LogicalKeyboardKey.numpad0:
        _applyScale(1);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  double _pointerDist() {
    final pts = _pointers.values.toList();
    return (pts[0] - pts[1]).distance;
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      _pinchStartDist = _pointerDist();
      _pinchBaseScale = _scale;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2 &&
        _pinchStartDist != null &&
        _pinchStartDist! > 0) {
      _applyScale(_pinchBaseScale * _pointerDist() / _pinchStartDist!);
    }
  }

  void _onPointerEnd(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _pinchStartDist = null;
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
      if (!_isVisibleDay(o.dayKey)) continue;
      if (_isAllDay(o)) {
        allDay.add(o);
      } else {
        timed.add(o);
      }
    }

    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerEnd,
        onPointerCancel: _onPointerEnd,
        child: Column(
          children: [
            _DayHeader(
              anchor: widget.anchor,
              dayCount: widget.dayCount,
              gutterWidth: gutterWidth,
            ),
            if (allDay.isNotEmpty)
              _AllDayStrip(
                occs: allDay,
                anchor: widget.anchor,
                dayCount: widget.dayCount,
                gutterWidth: gutterWidth,
                onTap: (id) => showEventDetails(context, id),
              ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                child: SizedBox(
                  height: 24 * hourHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HourGutter(hourHeight: hourHeight, width: gutterWidth),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (ctx, cons) {
                            final colW = cons.maxWidth / widget.dayCount;
                          _lastColW = colW;
                            return Stack(
                              children: [
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (d) =>
                                      _tapEmpty(d.localPosition, colW),
                                  child: CustomPaint(
                                    size: Size(cons.maxWidth, 24 * hourHeight),
                                    painter: _TimelinePainter(
                                      anchor: widget.anchor,
                                      dayCount: widget.dayCount,
                                      hourHeight: hourHeight,
                                      now: DateTime.now(),
                                      primary: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                ),
                                for (final o in timed) _eventBlock(o, colW),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const Map<String, Color> _googleColors = {
    '1': Color(0xFF7986CB),
    '2': Color(0xFF33B679),
    '3': Color(0xFF8E24AA),
    '4': Color(0xFFE67C73),
    '5': Color(0xFFF6BF26),
    '6': Color(0xFF3F51B5),
    '7': Color(0xFF039BE5),
    '8': Color(0xFF0B8043),
    '9': Color(0xFFD50000),
    '10': Color(0xFF303F9F),
    '11': Color(0xFF616161),
  };

  Color _eventColor(BuildContext context, String? colorId) {
    if (colorId != null && _googleColors.containsKey(colorId)) {
      return _googleColors[colorId]!;
    }
    return Theme.of(context).colorScheme.primary;
  }

  bool _isVisibleDay(String dayKeyValue) {
    for (var i = 0; i < widget.dayCount; i++) {
      if (dateKey(_dayStart(i)) == dayKeyValue) return true;
    }
    return false;
  }

  bool _isAllDay(OccurrenceCacheData o) {
    return (o.endUtc - o.startUtc) >= const Duration(hours: 23).inMilliseconds;
  }

  Widget _eventBlock(OccurrenceCacheData o, double colW) {
    final s = DateTime.fromMillisecondsSinceEpoch(o.startUtc);
    final e = DateTime.fromMillisecondsSinceEpoch(o.endUtc);
    var dayIdx = 0;
    for (var i = 0; i < widget.dayCount; i++) {
      if (dateKey(_dayStart(i)) == o.dayKey) {
        dayIdx = i;
        break;
      }
    }
    var y0 = (s.hour * 60 + s.minute + s.second / 60) / 60 * hourHeight;
    var y1 = (e.hour * 60 + e.minute + e.second / 60) / 60 * hourHeight;
    if (y1 - y0 < 20) y1 = y0 + 20;
    if (o.eventId == _dragId) {
      y0 += _dragDy;
      y1 += _dragDy;
    } else if (_dragOffset != 0 && o.eventId == _pendingMovedId) {
      y0 += _dragOffset;
      y1 += _dragOffset;
    }
    final title = o.title ?? '…';
    final leftShift = (o.eventId == _dragId)
        ? _dragDayDelta * colW
        : (_pendingMovedId == o.eventId ? _dragXOffset : 0.0);
    return Positioned(
      left: dayIdx * colW + 2 + leftShift,
      top: y0,
      width: colW - 4,
      height: y1 - y0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showEventDetails(context, o.eventId),
        onLongPressStart: (_) => setState(() {
          _dragId = o.eventId;
          _dragDy = 0;
          _dragDayDelta = 0;
        }),
        onLongPressMoveUpdate: (d) {
          if (_dragId != o.eventId) return;
          final dayDelta = (d.offsetFromOrigin.dx / _lastColW).round();
          final snap = (d.offsetFromOrigin.dy / hourHeight * 60 / 15)
                  .round() *
              15 /
              60 *
              hourHeight;
          setState(() {
            _dragDy = snap;
            _dragDayDelta = dayDelta;
          });
        },
        onLongPressEnd: (_) {
          if (_dragId == o.eventId) _dragEnd();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: _eventColor(context, o.colorId).withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ),
      ),
    );
  }

  void _tapEmpty(Offset pos, double colW) {
    final dayIdx = (pos.dx / colW).floor().clamp(0, widget.dayCount - 1);
    final hour = (pos.dy / hourHeight).floor().clamp(0, 23);
    showEventEditor(context, initialDay: _dayStart(dayIdx), initialHour: hour);
  }

  Future<void> _dragEnd() async {
    final id = _dragId;
    final dy = _dragDy;
    final dayDelta = _dragDayDelta;
    setState(() {
      _dragId = null;
      _dragDy = 0;
      _dragDayDelta = 0;
      _pendingMovedId = id;
      _dragOffset = dy;
      _dragXOffset = dayDelta * _lastColW;
    });
    if (id == null) return;
    final snapMin = (dy / hourHeight * 60).round();
    final snapped = (snapMin / 15).round() * 15;
    if (snapped == 0) return;
    final repo = ref.read(eventRepositoryProvider);
    final master = await (repo.dbSelect()..where((e) => e.id.equals(id)))
        .getSingleOrNull();
    if (master == null || !mounted) return;
    if (master.isAllDay || master.startUtc == null) return;
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
      if (scope == null || !mounted) return;
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
    if (mounted) {
      // Rebuild occurrence cache so the moved event reappears immediately.
      try {
        final window = ref.read(calendarStateProvider);
        await ref
            .read(occurrenceRepositoryProvider)
            .rebuildWindow(
              windowStartUtc: window.fromUtc,
              windowEndUtc: window.toUtc,
            );
      } catch (_) {
        // Best-effort; next navigation rebuilds.
      }
      if (mounted) {
        setState(() {
          _dragOffset = 0;
          _pendingMovedId = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Event moved')));
      }
    }
  }
}

class _HourGutter extends StatelessWidget {
  const _HourGutter({required this.hourHeight, required this.width});

  final double hourHeight;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 24 * hourHeight,
      child: Stack(
        children: [
          for (var h = 0; h < 24; h++)
            Positioned(
              top: h * hourHeight - 7,
              right: 4,
              child: Text(
                '${h.toString().padLeft(2, '0')}:00',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.anchor,
    required this.dayCount,
    required this.gutterWidth,
  });

  final DateTime anchor;
  final int dayCount;
  final double gutterWidth;

  static const _wd = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Row(
      children: [
        SizedBox(width: gutterWidth),
        for (var i = 0; i < dayCount; i++)
          Expanded(child: _dayCell(context, i, now)),
      ],
    );
  }

  Widget _dayCell(BuildContext context, int i, DateTime now) {
    final day = DateTime(
      anchor.year,
      anchor.month,
      anchor.day,
    ).add(Duration(days: i));
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    final color = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _wd[(day.weekday - 1) % 7],
            style: Theme.of(context).textTheme.labelSmall,
          ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: isToday
                ? BoxDecoration(color: color.primary, shape: BoxShape.circle)
                : null,
            child: Text(
              '${day.day}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: isToday ? color.onPrimary : null,
                fontWeight: isToday ? FontWeight.bold : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AllDayStrip extends StatelessWidget {
  const _AllDayStrip({
    required this.occs,
    required this.anchor,
    required this.dayCount,
    required this.gutterWidth,
    required this.onTap,
  });

  final List<OccurrenceCacheData> occs;
  final DateTime anchor;
  final int dayCount;
  final double gutterWidth;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: gutterWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'All-day',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
        for (var i = 0; i < dayCount; i++) Expanded(child: _dayChips(i)),
      ],
    );
  }

  Widget _dayChips(int i) {
    final day = DateTime(
      anchor.year,
      anchor.month,
      anchor.day,
    ).add(Duration(days: i));
    final key = dateKey(day);
    final mine = occs.where((o) => o.dayKey == key).take(3).toList();
    if (mine.isEmpty) return const SizedBox(height: 8);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final o in mine)
          Builder(
            builder: (ctx) => Padding(
              padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
              child: InkWell(
                onTap: () => onTap(o.eventId),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    o.title ?? 'All-day',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(ctx).textTheme.labelSmall,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.anchor,
    required this.dayCount,
    required this.hourHeight,
    required this.now,
    required this.primary,
  });

  final DateTime anchor;
  final int dayCount;
  final double hourHeight;
  final DateTime now;
  final Color primary;

  @override
  void paint(Canvas canvas, Size size) {
    final colW = size.width / dayCount;
    final grid = Paint()..color = primary.withValues(alpha: 0.12);
    for (var h = 0; h <= 24; h++) {
      canvas.drawLine(
        Offset(0, h * hourHeight),
        Offset(size.width, h * hourHeight),
        grid,
      );
    }
    for (var i = 0; i <= dayCount; i++) {
      canvas.drawLine(
        Offset(i * colW, 0),
        Offset(i * colW, 24 * hourHeight),
        grid,
      );
    }
    for (var i = 0; i < dayCount; i++) {
      final day = DateTime(
        anchor.year,
        anchor.month,
        anchor.day,
      ).add(Duration(days: i));
      if (day.year == now.year &&
          day.month == now.month &&
          day.day == now.day) {
        final y = (now.hour * 60 + now.minute) / 60 * hourHeight;
        canvas.drawLine(
          Offset(i * colW, y),
          Offset((i + 1) * colW, y),
          Paint()
            ..color = Colors.red
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.anchor != anchor || old.dayCount != dayCount;
}
