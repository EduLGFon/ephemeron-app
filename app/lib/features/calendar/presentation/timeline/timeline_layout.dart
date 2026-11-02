// Day-column overlap layout: side-by-side columns plus recursive nesting.
// Siblings that overlap split the width. An event that fully contains another
// becomes its parent: the parent keeps the full lane as background and the
// children are laid out inside it (inset). Nesting is recursive, so a 4h event
// can contain a 2h event that contains a 1h event.
class TimelineItem {
  const TimelineItem({
    required this.id,
    required this.startMin,
    required this.endMin,
  });

  final String id;
  final double startMin;
  final double endMin;

  double get duration => endMin - startMin;
}

class TimelinePlacement {
  const TimelinePlacement({
    required this.id,
    required this.left,
    required this.width,
    required this.depth,
    required this.hasChildren,
  });

  final String id;
  final double left;
  final double width;
  final int depth;
  final bool hasChildren;
}

bool _overlaps(TimelineItem a, TimelineItem b) {
  return a.startMin < b.endMin && b.startMin < a.endMin;
}

bool _contains(TimelineItem parent, TimelineItem child) {
  if (identical(parent, child) || parent.id == child.id) return false;
  if (parent.startMin > child.startMin || child.endMin > parent.endMin) {
    return false;
  }
  // Equal intervals are siblings, not parent/child, so they split evenly.
  if (parent.startMin == child.startMin && parent.endMin == child.endMin) {
    return false;
  }
  return parent.duration > child.duration;
}

/// Computes normalized [0, 1] horizontal rects for one day column.
Map<String, TimelinePlacement> layoutDayEvents(List<TimelineItem> input) {
  final items = <TimelineItem>[];
  for (final it in input) {
    var s = it.startMin;
    var e = it.endMin;
    if (e <= s) e = s + 30;
    items.add(TimelineItem(id: it.id, startMin: s, endMin: e));
  }
  final out = <String, TimelinePlacement>{};
  if (items.isEmpty) return out;
  if (items.length == 1) {
    final it = items.first;
    out[it.id] = const TimelinePlacement(
      id: '',
      left: 0,
      width: 1,
      depth: 0,
      hasChildren: false,
    )._withId(it.id);
    return out;
  }

  // Parent = smallest strictly-containing event (tightest container).
  final byId = {for (final it in items) it.id: it};
  final parentOf = <String, String?>{for (final it in items) it.id: null};
  for (final child in items) {
    TimelineItem? best;
    for (final cand in items) {
      if (!_contains(cand, child)) continue;
      if (best == null || cand.duration < best.duration) best = cand;
    }
    parentOf[child.id] = best?.id;
  }
  final childrenOf = <String, List<TimelineItem>>{};
  final roots = <TimelineItem>[];
  for (final it in items) {
    final p = parentOf[it.id];
    if (p == null) {
      roots.add(it);
    } else {
      childrenOf.putIfAbsent(p, () => []).add(it);
    }
  }

  void layoutLevel(List<TimelineItem> nodes, double x0, double x1, int depth) {
    if (nodes.isEmpty) return;
    final sorted = List<TimelineItem>.of(nodes)
      ..sort((a, b) {
        final c = a.startMin.compareTo(b.startMin);
        if (c != 0) return c;
        return b.duration.compareTo(a.duration);
      });
    // Split into overlap clusters. Touching edges share the full width.
    final clusters = <List<TimelineItem>>[];
    var cur = <TimelineItem>[sorted.first];
    var curMaxEnd = sorted.first.endMin;
    for (var i = 1; i < sorted.length; i++) {
      final it = sorted[i];
      if (it.startMin >= curMaxEnd) {
        clusters.add(cur);
        cur = [it];
        curMaxEnd = it.endMin;
      } else {
        cur.add(it);
        if (it.endMin > curMaxEnd) curMaxEnd = it.endMin;
      }
    }
    clusters.add(cur);

    for (final cluster in clusters) {
      if (cluster.length == 1) {
        final it = cluster.first;
        _place(it, x0, x1, depth, out, byId, childrenOf, layoutLevel);
        continue;
      }
      // Greedy interval coloring into columns.
      final cols = <double>[];
      final colOf = <String, int>{};
      for (final it in cluster) {
        var placed = -1;
        for (var c = 0; c < cols.length; c++) {
          if (it.startMin >= cols[c]) {
            placed = c;
            break;
          }
        }
        if (placed == -1) {
          placed = cols.length;
          cols.add(it.endMin);
        } else {
          cols[placed] = it.endMin;
        }
        colOf[it.id] = placed;
      }
      final n = cols.length;
      for (final it in cluster) {
        final col = colOf[it.id]!;
        // Expand right while no overlapping event occupies the span.
        var span = 1;
        outer:
        while (col + span < n) {
          for (final other in cluster) {
            if (other.id == it.id) continue;
            final oc = colOf[other.id]!;
            if (oc < col || oc > col + span) continue;
            if (_overlaps(it, other)) break outer;
          }
          span++;
        }
        final w = (x1 - x0) / n;
        _place(
          it,
          x0 + col * w,
          x0 + (col + span) * w,
          depth,
          out,
          byId,
          childrenOf,
          layoutLevel,
        );
      }
    }
  }

  layoutLevel(roots, 0, 1, 0);
  // Safety: every item must have a placement even if logic missed one.
  for (final it in items) {
    out.putIfAbsent(
      it.id,
      () => TimelinePlacement(
        id: it.id,
        left: 0,
        width: 1,
        depth: 0,
        hasChildren: false,
      ),
    );
  }
  return out;
}

void _place(
  TimelineItem it,
  double x0,
  double x1,
  int depth,
  Map<String, TimelinePlacement> out,
  Map<String, TimelineItem> byId,
  Map<String, List<TimelineItem>> childrenOf,
  void Function(List<TimelineItem>, double, double, int) recurse,
) {
  final kids = childrenOf[it.id] ?? const <TimelineItem>[];
  out[it.id] = TimelinePlacement(
    id: it.id,
    left: x0,
    width: (x1 - x0).clamp(0.0, 1.0),
    depth: depth,
    hasChildren: kids.isNotEmpty,
  );
  if (kids.isEmpty) return;
  // Inset children so the parent rim stays visible on the left.
  final inset = ((x1 - x0) * 0.12).clamp(0.02, 0.09);
  recurse(
    kids,
    (x0 + inset).clamp(0.0, 1.0),
    (x1 - 0.005).clamp(0.0, 1.0),
    depth + 1,
  );
}

extension on TimelinePlacement {
  TimelinePlacement _withId(String id) => TimelinePlacement(
    id: id,
    left: left,
    width: width,
    depth: depth,
    hasChildren: hasChildren,
  );
}
