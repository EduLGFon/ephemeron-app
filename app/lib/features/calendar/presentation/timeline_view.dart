// N-day / day timeline: custom painter, current-time line, tap-empty
// to create, tap event for details, vertical drag to move with
// 15-minute snapping (scope-asked for recurring).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/time.dart';
import '../../../data/drift/app_database.dart';
import '../../../data/repositories/event_repository.dart';
import '../application/calendar_providers.dart';
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
  static const double hourHeight = 56;
  String? _dragId;
  double _dragDy = 0;

  DateTime _dayStart(int i) {
    final a = widget.anchor;
    return DateTime(a.year, a.month, a.day).add(Duration(days: i));
  }

  @override
  Widget build(BuildContext context) {
    final window = ref.watch(calendarStateProvider);
    final occAsync = ref.watch(windowOccurrencesProvider(window));
    final occs = occAsync.valueOrNull ?? const <OccurrenceCacheData>[];
    final width = MediaQuery.of(context).size.width - 48;
    final colW = width / widget.dayCount;
    return SingleChildScrollView(
      child: SizedBox(
        height: 24 * hourHeight,
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: CustomPaint(
                  painter: _HoursPainter(hourHeight: hourHeight)),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (ctx, cons) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _tapEmpty(d.localPosition, colW),
                    onVerticalDragStart: (d) =>
                        _dragStart(d.localPosition, occs, colW),
                    onVerticalDragUpdate: (d) => setState(
                        () => _dragDy += d.delta.dy),
                    onVerticalDragEnd: (_) => _dragEnd(occs, colW),
                    child: CustomPaint(
                      size: Size(cons.maxWidth, 24 * hourHeight),
                      painter: _TimelinePainter(
                        occs: occs,
                        anchor: widget.anchor,
                        dayCount: widget.dayCount,
                        hourHeight: hourHeight,
                        now: DateTime.now(),
                        dragId: _dragId,
                        dragDy: _dragDy,
                        primary:
                            Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _tapEmpty(Offset pos, double colW) {
    final dayIdx = (pos.dx / colW).floor().clamp(0, widget.dayCount - 1);
    final hour = (pos.dy / hourHeight).floor().clamp(0, 23);
    showEventEditor(context,
        initialDay: _dayStart(dayIdx), initialHour: hour);
  }

  void _dragStart(
      Offset pos, List<OccurrenceCacheData> occs, double colW) {
    final dayIdx = (pos.dx / colW).floor().clamp(0, widget.dayCount - 1);
    final day = _dayStart(dayIdx);
    final tappedMin = (pos.dy / hourHeight * 60).round();
    for (final o in occs) {
      if (o.dayKey != dateKey(day)) continue;
      final s = DateTime.fromMillisecondsSinceEpoch(o.startUtc);
      final e = DateTime.fromMillisecondsSinceEpoch(o.endUtc);
      final sMin = s.hour * 60 + s.minute;
      final eMin = e.hour * 60 + e.minute;
      if (tappedMin >= sMin && tappedMin <= eMin) {
        setState(() {
          _dragId = o.eventId;
          _dragDy = 0;
        });
        return;
      }
    }
  }

  Future<void> _dragEnd(
      List<OccurrenceCacheData> occs, double colW) async {
    final id = _dragId;
    if (id == null) return;
    setState(() => _dragId = null);
    final snapMin = (_dragDy / hourHeight * 60).round();
    final snapped = (snapMin / 15).round() * 15;
    if (snapped == 0) return;
    final repo = ref.read(eventRepositoryProvider);
    final master = await (repo.dbSelect()
          ..where((e) => e.id.equals(id)))
        .getSingleOrNull();
    if (master == null || !mounted) return;
    if (master.rrule != null && master.rrule!.isNotEmpty) {
      final scope = await showScopeSheet(context);
      if (scope == null || !mounted) return;
      final orig = master.startUtc == null
          ? DateTime.now().toUtc()
          : DateTime.fromMillisecondsSinceEpoch(master.startUtc!,
              isUtc: true);
      await repo.editOccurrence(id, orig,
          scope: scope,
          startUtc: orig.add(Duration(minutes: snapped)),
          endUtc: DateTime.fromMillisecondsSinceEpoch(
                  master.endUtc ?? orig.millisecondsSinceEpoch,
                  isUtc: true)
              .add(Duration(minutes: snapped)));
    } else {
      await repo.editOccurrence(
          id,
          master.startUtc == null
              ? DateTime.now().toUtc()
              : DateTime.fromMillisecondsSinceEpoch(master.startUtc!,
                  isUtc: true),
          scope: EditScope.all,
          startUtc: DateTime.fromMillisecondsSinceEpoch(master.startUtc!,
                  isUtc: true)
              .add(Duration(minutes: snapped)),
          endUtc: DateTime.fromMillisecondsSinceEpoch(
                  master.endUtc ?? master.startUtc!,
                  isUtc: true)
              .add(Duration(minutes: snapped)));
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event moved')),
      );
    }
  }
}

class _HoursPainter extends CustomPainter {
  _HoursPainter({required this.hourHeight});
  final double hourHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var h = 0; h < 24; h++) {
      tp.text = TextSpan(
          text: '${h.toString().padLeft(2, '0')}:00',
          style: const TextStyle(fontSize: 10, color: Colors.grey));
      tp.layout();
      tp.paint(canvas, Offset(4, h * hourHeight - 6));
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.occs,
    required this.anchor,
    required this.dayCount,
    required this.hourHeight,
    required this.now,
    required this.dragId,
    required this.dragDy,
    required this.primary,
  });

  final List<OccurrenceCacheData> occs;
  final DateTime anchor;
  final int dayCount;
  final double hourHeight;
  final DateTime now;
  final String? dragId;
  final double dragDy;
  final Color primary;

  @override
  void paint(Canvas canvas, Size size) {
    final colW = size.width / dayCount;
    final grid = Paint()..color = primary.withValues(alpha: 0.12);
    for (var h = 0; h <= 24; h++) {
      canvas.drawLine(Offset(0, h * hourHeight),
          Offset(size.width, h * hourHeight), grid);
    }
    for (var i = 0; i <= dayCount; i++) {
      canvas.drawLine(Offset(i * colW, 0),
          Offset(i * colW, 24 * hourHeight), grid);
    }
    for (var i = 0; i < dayCount; i++) {
      final day =
          DateTime(anchor.year, anchor.month, anchor.day)
              .add(Duration(days: i));
      if (_isToday(day)) {
        final y = (now.hour * 60 + now.minute) / 60 * hourHeight;
        canvas.drawLine(Offset(i * colW, y),
            Offset((i + 1) * colW, y), Paint()..color = Colors.red);
      }
    }
    final block = Paint()..color = primary.withValues(alpha: 0.85);
    for (final o in occs) {
      final s = DateTime.fromMillisecondsSinceEpoch(o.startUtc);
      final e = DateTime.fromMillisecondsSinceEpoch(o.endUtc);
      for (var i = 0; i < dayCount; i++) {
        final day =
            DateTime(anchor.year, anchor.month, anchor.day)
                .add(Duration(days: i));
        if (o.dayKey != dateKey(day)) continue;
        var y0 = (s.hour * 60 + s.minute) / 60 * hourHeight;
        var y1 = (e.hour * 60 + e.minute) / 60 * hourHeight;
        if (y1 - y0 < 20) y1 = y0 + 20;
        if (o.eventId == dragId) {
          y0 += dragDy;
          y1 += dragDy;
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(
                  i * colW + 2, y0, colW - 4, y1 - y0),
              const Radius.circular(4)),
          block,
        );
      }
    }
  }

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.occs != occs || old.dragDy != dragDy || old.dragId != dragId;
}
