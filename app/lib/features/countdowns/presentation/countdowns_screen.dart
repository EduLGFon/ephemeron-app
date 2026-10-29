// Countdowns screen: upcoming/passed groups, relative distances,
// editor, delete with undo.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/drift/app_database.dart';
import '../../../domain/countdowns/countdown.dart';
import '../application/countdowns_providers.dart';
import 'countdown_editor_sheet.dart';

class CountdownsScreen extends ConsumerWidget {
  const CountdownsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countdownsAsync = ref.watch(countdownsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Countdowns')),
      body: countdownsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load countdowns.'),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => ref.invalidate(countdownsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (countdowns) {
          if (countdowns.isEmpty) return const _EmptyState();
          final today = DateTime.now();
          final dated = <({Countdown c, DateTime next, int days})>[];
          final undated = <Countdown>[];
          for (final c in countdowns) {
            final parsed = _parseDate(c.targetDate);
            if (parsed == null) {
              undated.add(c);
              continue;
            }
            // One-time countdowns use the full stored date; yearly ones
            // roll to the next occurrence via the domain helper.
            final next = c.yearlyRepeat
                ? countdownNextDate(
                    month: parsed.month,
                    day: parsed.day,
                    today: today,
                    yearlyRepeat: true,
                  )
                : DateTime(parsed.year, parsed.month, parsed.day);
            dated.add((c: c, next: next, days: daysUntil(next, today)));
          }
          dated.sort((a, b) => a.days.compareTo(b.days));
          final upcoming = dated.where((d) => d.days >= 0).toList();
          final passed = dated.where((d) => d.days < 0).toList();
          return ListView(
            children: [
              if (upcoming.isNotEmpty) ...[
                const _GroupHeader(title: 'Upcoming'),
                for (final d in upcoming) _CountdownTile(entry: d),
              ],
              if (passed.isNotEmpty) ...[
                const _GroupHeader(title: 'Passed'),
                for (final d in passed) _CountdownTile(entry: d),
              ],
              if (undated.isNotEmpty) ...[
                const _GroupHeader(title: 'No date'),
                for (final c in undated) _UndatedTile(countdown: c),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showCountdownEditor(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

DateTime? _parseDate(String? targetDate) {
  if (targetDate == null || targetDate.isEmpty) return null;
  final p = targetDate.split('-');
  if (p.length != 3) return null;
  final y = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  final d = int.tryParse(p[2]);
  if (y == null || m == null || d == null) return null;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return DateTime(y, m, d);
}

String _relativeText(int days) {
  if (days == 0) return 'today';
  if (days == 1) return 'tomorrow';
  if (days > 1) return 'in $days days';
  if (days == -1) return 'yesterday';
  return '${-days} days ago';
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _CountdownTile extends ConsumerWidget {
  const _CountdownTile({required this.entry});

  final ({Countdown c, DateTime next, int days}) entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = entry.c;
    final detail = StringBuffer(_relativeText(entry.days));
    detail.write(' - ${entry.next.year}-${entry.next.month}-${entry.next.day}');
    if (c.yearlyRepeat) {
      final birth = _parseDate(c.targetDate);
      if (c.showAge && birth != null) {
        detail.write(' - turns ${entry.next.year - birth.year}');
      } else {
        detail.write(' - yearly');
      }
    }
    return ListTile(
      leading: const Icon(Icons.hourglass_bottom_outlined),
      title: Text(c.title),
      subtitle: Text(detail.toString()),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Delete',
        onPressed: () => _delete(context, ref),
      ),
      onTap: () => showCountdownEditor(context, countdown: c),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(countdownRepositoryProvider);
    await repo.deleteCountdown(entry.c.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Countdown deleted.'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => repo.restoreCountdown(entry.c.id),
        ),
      ),
    );
  }
}

class _UndatedTile extends ConsumerWidget {
  const _UndatedTile({required this.countdown});

  final Countdown countdown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.hourglass_empty_outlined),
      title: Text(countdown.title),
      onTap: () => showCountdownEditor(context, countdown: countdown),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.hourglass_bottom_outlined, size: 48),
          const SizedBox(height: 12),
          Text(
            'No countdowns yet.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => showCountdownEditor(context),
            child: const Text('Add countdown'),
          ),
        ],
      ),
    );
  }
}
