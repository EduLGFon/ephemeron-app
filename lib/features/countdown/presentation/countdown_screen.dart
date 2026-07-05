import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/local/database.dart';
import '../application/countdown_providers.dart';
import '../domain/countdown_status.dart';
import '../domain/countdown_type.dart';
import 'countdown_form_sheet.dart';
import 'countdown_template_picker.dart';

class CountdownScreen extends ConsumerWidget {
  const CountdownScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countdownsAsync = ref.watch(countdownsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Countdown')),
      body: countdownsAsync.when(
        data: (countdowns) {
          if (countdowns.isEmpty) {
            return Center(
              child: Text(
                'No countdowns yet',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            );
          }
          final withStatus = [
            for (final countdown in countdowns)
              (
                countdown: countdown,
                status: CountdownStatus.compute(
                  targetDate: countdown.targetDate,
                  isYearly: countdown.isYearly,
                  showAge: countdown.showAge,
                ),
              ),
          ]..sort((a, b) => a.status.days.compareTo(b.status.days));

          return ListView.builder(
            itemCount: withStatus.length,
            itemBuilder: (context, index) {
              final entry = withStatus[index];
              return _CountdownTile(
                countdown: entry.countdown,
                status: entry.status,
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Could not load countdowns: $error')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showCountdownTemplatePicker(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _CountdownTile extends ConsumerWidget {
  const _CountdownTile({required this.countdown, required this.status});

  final Countdown countdown;
  final CountdownStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = CountdownType.values.byName(countdown.type);
    final theme = Theme.of(context);

    final daysLabel = status.days == 0
        ? 'Today'
        : status.isFuture
        ? '${status.days} day${status.days == 1 ? '' : 's'} left'
        : '${status.days} day${status.days == 1 ? '' : 's'} since';

    return Dismissible(
      key: ValueKey(countdown.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) =>
          ref.read(countdownRepositoryProvider).deleteCountdown(countdown.id),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.amberDim,
          child: Text(
            '${status.days}',
            style: const TextStyle(fontSize: 12, color: AppColors.textLight),
          ),
        ),
        title: Text(countdown.title),
        subtitle: Text(
          status.age != null ? '$daysLabel · turns ${status.age}' : daysLabel,
        ),
        trailing: Text(type.label, style: theme.textTheme.labelSmall),
        onTap: () => showCountdownFormSheet(
          context,
          type: type,
          existingCountdown: countdown,
        ),
      ),
    );
  }
}
