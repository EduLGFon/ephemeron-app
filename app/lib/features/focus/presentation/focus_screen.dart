import 'package:ephemeron/core/time/time.dart';

// Focus screen: timestamp-based timer (elapsed computed per frame
// while visible), one native end alarm, stats, session history.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/platform/app_permissions.dart';
import '../../../core/platform/system_launcher.dart';
import '../../../data/drift/app_database.dart';
import '../../../domain/alarms/alarm_preset.dart';
import '../../alarms/data/alarm_scheduler.dart';
import '../../alarms/presentation/alarm_preset_picker.dart';
import '../../sync/application/pending_operations.dart';
import '../../../domain/habits/date_key.dart';
import '../../habits/application/habits_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../application/focus_providers.dart';
import 'focus_stats_screen.dart';

part 'focus_screen_start.dart';
part 'focus_screen_running.dart';
part 'focus_screen_shared.dart';

const _focusPresets = [15, 25, 50];
const _breakPresets = [5, 10, 15];

enum _FocusMode { focus, breakTime, stopwatch }

Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
  final sessions = ref.read(recentFocusSessionsProvider).value ?? const [];
  final buf = StringBuffer('start,end,minutes,phase,note\n');
  for (final s in sessions) {
    buf.writeln(
      '${s.startUtc},${s.endUtc ?? ''},${s.endUtc == null ? '' : ((s.endUtc! - s.startUtc) / msPerMinute).floor()},${s.phase ?? ''},${(s.note ?? '').replaceAll(',', ';')}',
    );
  }
  await Clipboard.setData(ClipboardData(text: buf.toString()));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Focus CSV copied to clipboard')),
    );
  }
}

class FocusScreen extends ConsumerWidget {
  const FocusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentAsync = ref.watch(currentFocusSessionProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Focus'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            tooltip: 'Monthly stats',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const FocusStatsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Export CSV',
            onPressed: () => _exportCsv(context, ref),
          ),
        ],
      ),
      body: currentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: OutlinedButton(
            onPressed: () => ref.invalidate(currentFocusSessionProvider),
            child: const Text('Retry'),
          ),
        ),
        data: (session) => session == null
            ? const _StartView()
            : _RunningView(session: session),
      ),
    );
  }
}

void _refresh(WidgetRef ref) {
  ref.invalidate(currentFocusSessionProvider);
  ref.invalidate(focusTodayMinutesProvider);
  ref.invalidate(focusWeekMinutesProvider);
  ref.invalidate(breakTodayMinutesProvider);
  ref.invalidate(breakWeekMinutesProvider);
  ref.invalidate(focusMonthMinutesProvider);
  ref.invalidate(breakMonthMinutesProvider);
  ref.invalidate(recentFocusSessionsProvider);
}

int _requestCode(String id) => id.hashCode & 0x7fffffff;

Future<void> _scheduleEndAlarm(FocusSession s) {
  final target = s.targetEndUtc;
  if (target == null) return Future.value();
  final preset = parseAlarmPreset(s.alarmPreset) ?? AlarmPreset.notification;
  final phase = s.phase ?? 'focus';
  final isBreak = phase == 'break';
  return AlarmScheduler.schedulePreset(
    requestCode: _requestCode(s.id),
    fireAtUtcMs: target,
    preset: preset,
    title: isBreak ? 'Break complete' : 'Focus session complete',
    body: '$phase session is over.',
    sourceType: 'focus',
    sourceId: s.id,
    phase: phase,
  );
}
