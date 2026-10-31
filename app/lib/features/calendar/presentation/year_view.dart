// Year heat-map: 12 mini month grids shaded by event counts.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/calendar_providers.dart';

class YearView extends ConsumerWidget {
  const YearView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = ref.watch(calendarStateProvider);
    final occAsync = ref.watch(windowOccurrencesProvider(window));
    final counts = <String, int>{};
    for (final o in occAsync.maybeWhen(
      data: (v) => v,
      orElse: () => const [],
    )) {
      final ym = o.dayKey.substring(0, 7);
      counts[ym] = (counts[ym] ?? 0) + 1;
    }
    final max = counts.values.fold(1, (a, b) => a > b ? a : b);
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.4,
      ),
      itemCount: 12,
      itemBuilder: (ctx, m) {
        final ym =
            '${window.anchor.year}-${(m + 1).toString().padLeft(2, '0')}';
        final c = counts[ym] ?? 0;
        return Card(
          color: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: 0.1 + 0.5 * c / max),
          child: Center(
            child: Text('${_name(m + 1)}\n$c', textAlign: TextAlign.center),
          ),
        );
      },
    );
  }

  String _name(int m) => DateFormat.MMM().format(DateTime(2000, m));
}
