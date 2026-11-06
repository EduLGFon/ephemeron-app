import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ephemeron/core/ui/app_sheet.dart';
import 'package:ephemeron/core/ui/escape_to_close.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/system_launcher.dart';
import '../../core/db/db_provider.dart';
import '../../app/session/session_restore.dart';
import '../../data/drift/app_database.dart';
import '../../features/alarms/application/alarm_action_handler.dart';
import '../../features/alarms/application/alarm_providers.dart';
import '../../features/alarms/data/fallback_alarm_engine.dart';
import '../../features/auth/application/auth_providers.dart';
import '../../features/calendar/application/calendar_providers.dart';
import '../../features/calendar/application/calendar_state.dart';
import '../../features/calendar/presentation/event_details_sheet.dart';
import '../../features/calendar/presentation/event_editor_sheet.dart';
import '../../features/calendar/presentation/timeline/timeline_now_controller.dart';
import '../../features/countdowns/presentation/countdown_editor_sheet.dart';
import '../../features/habits/presentation/habit_editor_sheet.dart';
import '../../features/notes/presentation/note_editor_screen.dart';
import '../../features/search/application/search_providers.dart';
import '../../features/settings/application/settings_providers.dart';
import '../../features/settings/presentation/onboarding_screen.dart';
import '../../features/sync/application/pending_operations.dart';
import '../../features/sync/application/sync_providers.dart';
import '../../features/tasks/presentation/quick_add_sheet.dart';
import '../../features/tasks/presentation/task_editor_sheet.dart';
import '../../data/services/home_widget_data_binder.dart';
import '../../data/services/week_widget_options.dart';
import '../../data/services/week_calendar_data.dart';
import 'app_sections.dart';
import '../../features/tasks/application/tasks_providers.dart';
import '../../features/habits/application/habits_providers.dart';
import '../../features/countdowns/application/countdowns_providers.dart';
import '../../features/notes/application/notes_providers.dart';
import '../../features/focus/application/focus_providers.dart';
import 'more_sheet.dart';

part 'app_shell/navigation.dart';
part 'app_shell/session_restore.dart';
part 'app_shell/sheet_restore.dart';
part 'app_shell/shortcuts.dart';
part 'app_shell/widget_actions.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  Map<ShortcutActivator, VoidCallback> _shortcuts =
      const <ShortcutActivator, VoidCallback>{};
  Timer? _widgetRefreshTimer;
  late final Future<void> _restoreFuture;
  StreamSubscription<String>? _widgetActionSub;
  late final Future<String?> _startupWidgetActionFuture;
  String? _pendingWidgetAction;
  bool _handlingWidgetAction = false;
  String? _handledWidgetAction;

  void _scheduleWidgetRefresh() {
    _widgetRefreshTimer?.cancel();
    _widgetRefreshTimer = Timer(const Duration(seconds: 2), () async {
      if (!mounted) return;
      try {
        await ref.read(homeWidgetDataBinderProvider).refreshAll();
      } catch (_) {}
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
    // Consume before restore applies state so a cold-start widget tap can
    // suppress conflicting tab/calendar restore and then be applied after.
    _startupWidgetActionFuture = SystemLauncher.consumeWidgetAction();
    _restoreFuture = _restoreSession();
    SystemLauncher.ensureWidgetActionHandler();
    _widgetActionSub = SystemLauncher.widgetActions.listen((action) {
      Future.microtask(() async {
        await _restoreFuture;
        if (!mounted) return;
        await _handleWidgetAction(action);
      });
    });
    // Everything below is non-critical for the first frame. Defer it until
    // after Flutter has painted so launch stays responsive.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startBackgroundWork());
  }

  Future<void> _startBackgroundWork() async {
    if (!mounted) return;
    // Apply destructive operations left pending by a previous session.
    ref.read(pendingOperationsProvider);
    // Restart the persisted auto-sync schedule on every launch.
    Future.microtask(() => ref.read(googleAutoSyncServiceProvider).start());
    Future.microtask(
      () => ref.read(backendAutoSyncServiceProvider).reschedule(),
    );
    // Rebuild the alarm window on every app open (rolling 48 h + 60).
    Future.microtask(() async {
      if (!mounted) return;
      try {
        final settings = await ref.read(settingsRepositoryProvider.future);
        await ref
            .read(alarmRepositoryProvider)
            .rebuildWindow(
              dueTomorrowEnabled: settings.taskDueTomorrowReminder,
            );
      } catch (_) {}
    });
    // A widget tap must win over the restored tab/view; otherwise the
    // async session restore can overwrite the requested calendar range.
    await _restoreFuture;
    if (!mounted) return;
    // Refresh home-screen widgets after startup settles so they do not
    // compete with the first calendar frame.
    _scheduleWidgetRefresh();
    // Handle Android share-target text and launcher shortcuts once the
    // first frame is up (needs a BuildContext for sheets/navigation).
    await _handleIntents();
  }

  @override
  void dispose() {
    _widgetRefreshTimer?.cancel();
    _widgetActionSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Widget taps while the app is already open only bring it forward;
    // consume the pending action on resume so deep links still work.
    if (state == AppLifecycleState.resumed) {
      Future.microtask(() async {
        await _restoreFuture;
        if (!mounted) return;
        await _handleWidgetAction();
      });
      _scheduleWidgetRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Widget refresh triggers: resubscribed on rebuild, previous
    // subscriptions are cancelled automatically by Riverpod.
    ref.listen(
      openTasksProvider(null),
      (prev, next) => _scheduleWidgetRefresh(),
    );
    ref.listen(habitsProvider(false), (prev, next) => _scheduleWidgetRefresh());
    ref.listen(countdownsProvider, (prev, next) => _scheduleWidgetRefresh());
    ref.listen(
      folderNotesProvider(null),
      (prev, next) => _scheduleWidgetRefresh(),
    );
    ref.listen(
      currentFocusSessionProvider,
      (prev, next) => _scheduleWidgetRefresh(),
    );
    ref.listen(
      upcomingAlarmsProvider,
      (prev, next) => _scheduleWidgetRefresh(),
    );
    ref.listen(occurrenceDirtyProvider, (prev, next) {
      if (next) _scheduleWidgetRefresh();
    });
    final orderAsync = ref.watch(settingsRepositoryProvider);
    final onboarded = orderAsync.maybeWhen(
      data: (r) => r.onboarded,
      orElse: () => true,
    );
    if (!onboarded) return const OnboardingScreen();
    final order = orderAsync.maybeWhen(
      data: (r) => r.navOrder,
      orElse: () => List<int>.generate(7, (i) => i),
    );
    final pinned = order.take(5).toList();
    final more = order.skip(5).toList();

    final shortcuts = _buildShortcuts();
    _shortcuts = shortcuts;
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (_isEditingText()) return KeyEventResult.ignored;
        KeyEventResult result = KeyEventResult.ignored;
        for (final activator in shortcuts.keys) {
          if (activator.accepts(event, HardwareKeyboard.instance)) {
            shortcuts[activator]!();
            result = KeyEventResult.handled;
          }
        }
        return result;
      },
      child: AlarmActionHandler(
        child: AlarmListener(
          child: Scaffold(
            body: widget.navigationShell,
            bottomNavigationBar: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: NavigationBar(
                selectedIndex:
                    pinned.contains(widget.navigationShell.currentIndex)
                    ? pinned.indexOf(widget.navigationShell.currentIndex)
                    : 5,
                onDestinationSelected: (i) {
                  if (i < 5) {
                    _onTabSelected(pinned[i]);
                  } else {
                    _showMore(context, more, order);
                  }
                },
                destinations: [
                  for (final idx in pinned)
                    NavigationDestination(
                      icon: Icon(AppSection.values[idx].icon),
                      label: AppSection.values[idx].title,
                    ),
                  const NavigationDestination(
                    icon: Icon(Icons.more_horiz),
                    label: 'More',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
