import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:device_calendar_plus/device_calendar_plus.dart' as dev_cal;

import '../../../core/theme/theme_palettes.dart';
import '../domain/calendar_event.dart';
import '../application/calendar_providers.dart';
import '../../quick_add/application/quick_add_provider.dart';
import '../../tasks/application/task_providers.dart';
import '../../habits/application/habit_providers.dart';
import '../../tasks/domain/task_recurrence.dart';
import '../../../presentation/widgets/recurrence_delete_dialog.dart';
import '../../../presentation/widgets/confirmation_dialog.dart';

class CalendarEventTile extends ConsumerWidget {
  const CalendarEventTile({
    super.key,
    required this.event,
    required this.palette,
  });

  final CalendarEvent event;
  final AppPalette palette;

  Color _getTileColor(String? colorId, AppPalette palette) {
    if (colorId != null) {
      if (colorId.startsWith('device:')) {
        final hex = colorId.substring(7);
        if (hex.isNotEmpty) {
          try {
            final c = hex.replaceAll('#', '');
            if (c.length == 8) {
              return Color(int.parse(c, radix: 16));
            } else if (c.length == 6) {
              return Color(int.parse('FF$c', radix: 16));
            }
          } catch (_) {}
        }
        return palette.primary;
      }
      if (colorId.startsWith('task:')) {
        final hex = colorId.substring(5);
        if (hex.isNotEmpty) {
          try {
            final c = hex.replaceAll('#', '');
            return Color(int.parse('FF$c', radix: 16));
          } catch (_) {}
        }
        return palette.primary;
      }
      if (colorId.startsWith('habit:')) {
        return palette.secondary;
      }
      final match = GoogleEventColor.options.firstWhere(
        (c) => c.id == colorId,
        orElse: () => GoogleEventColor.options[6],
      );
      return Color(match.hex);
    }
    return Color(GoogleEventColor.options[6].hex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventColor = _getTileColor(event.colorId, palette);

    return Container(
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: palette.isAmoled ? 1.0 : 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.text.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 12,
              height: 40,
              decoration: BoxDecoration(
                color: eventColor,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(event.title,
                      style: TextStyle(
                          color: palette.text, fontWeight: FontWeight.bold)),
                ),
                if (event.selfResponseStatus == RsvpStatus.accepted ||
                    event.selfResponseStatus == RsvpStatus.acceptedVirtually)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.check_circle_outline,
                        size: 16, color: palette.primary),
                  )
                else if (event.selfResponseStatus == RsvpStatus.declined)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.cancel_outlined,
                        size: 16, color: Colors.redAccent),
                  )
                else if (event.selfResponseStatus == RsvpStatus.tentative)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.help_outline,
                        size: 16, color: palette.text.withValues(alpha: 0.5)),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  event.isAllDay
                      ? 'All day'
                      : '${_formatTime(event.start)} – ${_formatTime(event.end)}'
                          '${event.location != null ? ' · ${event.location}' : ''}',
                  style: TextStyle(color: palette.text.withValues(alpha: 0.6)),
                ),
                if (event.tags.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    children: event.tags
                        .map((tag) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: eventColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(tag,
                                  style: TextStyle(
                                      color: eventColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
            onTap: () async {
              if (event.id.startsWith('task:')) {
                final taskId = event.id.substring(5);
                final task =
                    await ref.read(taskRepositoryProvider).getTask(taskId);
                if (task != null && context.mounted) {
                  ref.read(quickAddProvider.notifier).expand(task);
                }
              } else if (event.id.startsWith('habit:')) {
                final habitId = event.id.split(':')[1];
                final habit =
                    await ref.read(habitRepositoryProvider).getHabit(habitId);
                if (habit != null && context.mounted) {
                  ref.read(quickAddProvider.notifier).expand(habit);
                }
              } else if (event.id.startsWith('device:')) {
                final parts = event.id.split(':');
                if (parts.length >= 3) {
                  final eventId = parts.skip(2).join(':');
                  await dev_cal.DeviceCalendar().showEventModal(eventId);
                  ref.invalidate(
                      monthEventsProvider(ref.read(focusedMonthProvider)));
                }
              } else {
                ref.read(quickAddProvider.notifier).expand(event);
              }
            },
            onLongPress: () => _confirmDelete(context, ref),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final localDt = dt.toLocal();
    return '${localDt.hour.toString().padLeft(2, '0')}:${localDt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final isTask = event.id.startsWith('task:');
    final isHabit = event.id.startsWith('habit:');

    if (isTask) {
      final taskId = event.id.substring(5);
      final task = await ref.read(taskRepositoryProvider).getTask(taskId);
      if (task != null) {
        final recurrence = TaskRecurrence.decode(task.recurrenceRule);
        if (recurrence.isRecurring) {
          final choice = await showRecurrenceDeleteDialog(
            context: context, // ignore: use_build_context_synchronously
            ref: ref,
            title: 'Delete Recurring Task?',
          );
          if (choice == null) return;
          if (choice == RecurrenceDeleteType.onlyThis) {
            final nextDue = recurrence.nextOccurrence(task.dueDate!);
            if (nextDue != null) {
              await ref
                  .read(taskRepositoryProvider)
                  .updateTask(taskId, dueDate: Value(nextDue));
            }
          } else {
            await ref.read(taskRepositoryProvider).softDeleteTask(taskId);
          }
        } else {
          final confirmed = await showConfirmationDialog(
            context: context, // ignore: use_build_context_synchronously
            ref: ref,
            title: 'Delete Task?',
            content:
                'Are you sure you want to delete this task? It will be moved to Trash.',
            confirmLabel: 'Delete',
            isDestructive: true,
          );
          if (confirmed) {
            await ref.read(taskRepositoryProvider).softDeleteTask(taskId);
          }
        }
      }
    } else if (isHabit) {
      final confirmed = await showConfirmationDialog(
        context: context,
        ref: ref,
        title: 'Delete Habit?',
        content: 'Are you sure you want to delete this habit?',
        confirmLabel: 'Delete',
        isDestructive: true,
      );
      if (confirmed) {
        final habitId = event.id.split(':')[1];
        await ref.read(habitRepositoryProvider).deleteHabit(habitId);
      }
    } else {
      if (event.id.startsWith('device:')) {
        final confirmed = await showConfirmationDialog(
          context: context,
          ref: ref,
          title: 'Delete Device Event?',
          content:
              'Are you sure you want to permanently delete this event from your phone\'s calendar?',
          confirmLabel: 'Delete',
          isDestructive: true,
        );
        if (confirmed) {
          final parts = event.id.split(':');
          if (parts.length >= 3) {
            final eventId = parts.skip(2).join(':');
            await ref
                .read(deviceCalendarRepositoryProvider)
                .deleteEvent(event.calendarId, eventId);
            ref.invalidate(
              monthEventsProvider(ref.read(focusedMonthProvider)),
            );
          }
        }
        return;
      }
      final isRecurringEvent = event.recurringEventId != null ||
          (event.recurrence != null && event.recurrence!.isNotEmpty);
      if (isRecurringEvent) {
        final choice = await showRecurrenceDeleteDialog(
          context: context,
          ref: ref,
          title: 'Delete Recurring Event?',
        );
        if (choice == null) return;

        if (choice == RecurrenceDeleteType.onlyThis) {
          await ref
              .read(calendarRepositoryProvider)
              .deleteEvent(event.id, calendarId: event.calendarId);
        } else if (choice == RecurrenceDeleteType.all) {
          await ref.read(calendarRepositoryProvider).deleteEvent(
              event.recurringEventId ?? event.id,
              calendarId: event.calendarId);
        } else if (choice == RecurrenceDeleteType.thisAndAllAfter) {
          await ref
              .read(calendarRepositoryProvider)
              .deleteThisAndFutureEvents(event);
        }
        ref.invalidate(
          monthEventsProvider(ref.read(focusedMonthProvider)),
        );
      } else {
        final confirmed = await showConfirmationDialog(
          context: context,
          ref: ref,
          title: 'Delete Event?',
          content: 'Are you sure you want to permanently delete this event?',
          confirmLabel: 'Delete',
          isDestructive: true,
        );
        if (confirmed) {
          await ref
              .read(calendarRepositoryProvider)
              .deleteEvent(event.id, calendarId: event.calendarId);
          ref.invalidate(
            monthEventsProvider(ref.read(focusedMonthProvider)),
          );
        }
      }
    }
  }
}
