// Focus stats screen: monthly calendar grid plus breakdowns by task,
// habit and time of day (last 30 days), and the DND-during-focus toggle.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/system_launcher.dart';
import '../../settings/application/settings_providers.dart';
import '../application/focus_providers.dart';

class FocusStatsScreen extends ConsumerStatefulWidget {
  const FocusStatsScreen({super.key});

  @override
  ConsumerState<FocusStatsScreen> createState() => _FocusStatsScreenState();
}

class _FocusStatsScreenState extends ConsumerState<FocusStatsScreen> {
  DateTime _month = DateTime.now().toUtc();

  @override
  Widget build(BuildContext context) {
    final daysAsync = ref.watch(focusMonthMinutesProvider(_month));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Focus stats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous month',
            onPressed: () => setState(() {
              _month = DateTime.utc(_month.year, _month.month - 1, 1);
            }),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next month',
            onPressed: () => setState(() {
              _month = DateTime.utc(_month.year, _month.month + 1, 1);
            }),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${_month.year}-${_month.month.toString().padLeft(2, '0')}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          daysAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Text('Could not load month.'),
            data: (days) => _MonthGrid(days: days, month: _month),
          ),
          const SizedBox(height: 16),
          Text('By task', style: Theme.of(context).textTheme.titleSmall),
          _Breakdown(provider: focusStatsByTaskProvider),
          const SizedBox(height: 8),
          Text('By habit', style: Theme.of(context).textTheme.titleSmall),
          _Breakdown(provider: focusStatsByHabitProvider),
          const SizedBox(height: 8),
          Text('By time of day', style: Theme.of(context).textTheme.titleSmall),
          _Breakdown(provider: focusStatsByTimeOfDayProvider),
          const SizedBox(height: 16),
          const _DndToggle(),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.days, required this.month});

  final List<int> days;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final max = days.fold<int>(1, (a, b) => b > a ? b : a);
    final firstWeekday = DateTime.utc(month.year, month.month, 1).weekday;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 0.8,
      ),
      itemCount: (firstWeekday - 1) + days.length,
      itemBuilder: (ctx, i) {
        if (i < firstWeekday - 1) return const SizedBox.shrink();
        final day = i - (firstWeekday - 1);
        final min = days[day];
        final intensity = min <= 0 ? 0.05 : 0.2 + 0.8 * (min / max);
        return Semantics(
          label: 'Day ${day + 1}: $min minutes',
          child: Card(
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: intensity),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${day + 1}'),
                  if (min > 0)
                    Text('$min', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Breakdown extends ConsumerWidget {
  const _Breakdown({required this.provider});

  final FutureProvider<List<(String, int)>> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    return async.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => const Text('Could not load.'),
      data: (rows) {
        if (rows.isEmpty) return const Text('No sessions yet.');
        final max = rows.fold<int>(1, (a, r) => r.$2 > a ? r.$2 : a);
        return Column(
          children: [
            for (final (label, min) in rows)
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      label.length > 18
                          ? '${label.substring(0, 18)}...'
                          : label,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: LinearProgressIndicator(
                      value: min / max,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 56,
                    child: Text('$min min', textAlign: TextAlign.end),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// Alarms-only DND while a focus session runs. Android only; when the
/// system access is missing the toggle opens system settings instead.
class _DndToggle extends ConsumerWidget {
  const _DndToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repoAsync = ref.watch(settingsRepositoryProvider);
    return repoAsync.maybeWhen(
      data: (repo) => SwitchListTile(
        title: const Text('Do Not Disturb during focus'),
        subtitle: Text(
          defaultTargetPlatform == TargetPlatform.android
              ? 'Alarms only while a session runs'
              : 'Android only',
        ),
        value: repo.focusDnd,
        onChanged: defaultTargetPlatform != TargetPlatform.android
            ? null
            : (v) async {
                if (v && !await SystemLauncher.hasDndAccess) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Grant Do Not Disturb access in system settings',
                        ),
                      ),
                    );
                  }
                  await SystemLauncher.openDndSettings();
                  return;
                }
                await repo.setFocusDnd(v);
                ref.invalidate(settingsRepositoryProvider);
              },
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}
