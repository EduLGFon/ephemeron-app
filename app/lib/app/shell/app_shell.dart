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

const List<LogicalKeyboardKey> _digitKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
];

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

  /// Opens quick add prefilled with shared text, jumps to the tab
  /// requested by a launcher shortcut, or routes a home-widget tap.
  /// No-ops on other platforms.
  Future<void> _handleIntents() async {
    if (!mounted) return;
    final shared = await SystemLauncher.consumeSharedText();
    if (shared != null && shared.trim().isNotEmpty && mounted) {
      await showQuickAdd(context, initialText: shared.trim());
    }
    if (!mounted) return;
    final action = await SystemLauncher.consumeLaunchAction();
    if (action != null && mounted) {
      switch (action) {
        case 'new_task':
          await showQuickAdd(context);
        case 'new_event':
          _onTabSelected(AppSection.calendar.index);
        case 'start_focus':
          _onTabSelected(AppSection.focus.index);
        case 'focus_start_break':
        case 'focus_start_focus':
          ref
              .read(pendingFocusNextProvider.notifier)
              .set(action == 'focus_start_break' ? 'break' : 'focus');
          _onTabSelected(AppSection.focus.index);
      }
    }
    if (!mounted) return;
    await _handleWidgetAction();
  }

  /// Routes a home-widget tap (new_task/search/week day/prev/next). Called
  /// on startup and on resume so taps work whether the app was closed or
  /// already open. Previous/next shifts the persisted widget anchor by one
  /// visible span and re-renders the widget in the foreground (the native
  /// provider cannot re-render the Flutter image on its own), then opens
  /// the calendar on the new range.
  Future<void> _handleWidgetAction([String? pendingAction]) async {
    if (!mounted) return;
    final widgetAction =
        pendingAction ??
        _pendingWidgetAction ??
        await SystemLauncher.consumeWidgetAction();
    if (pendingAction == null) _pendingWidgetAction = null;
    debugPrint('[widget] action=$widgetAction mounted=$mounted');
    if (widgetAction == null || !mounted) return;
    if (_handlingWidgetAction) return;
    if (_handledWidgetAction == widgetAction && pendingAction == null) return;
    _handlingWidgetAction = true;
    _handledWidgetAction = widgetAction;
    try {
      if (widgetAction == 'new_task') {
        await showQuickAdd(context);
        return;
      } else if (widgetAction == 'search') {
        GoRouter.of(context).push('/search');
        try {
          final repo = await ref.read(settingsRepositoryProvider.future);
          await repo.setLastRoute('/search');
        } catch (_) {}
        return;
      } else if (widgetAction == 'focus_start_break' ||
          widgetAction == 'focus_start_focus') {
        ref
            .read(pendingFocusNextProvider.notifier)
            .set(widgetAction == 'focus_start_break' ? 'break' : 'focus');
        _onTabSelected(AppSection.focus.index);
        return;
      }
      final tap = parseWeekWidgetAction(widgetAction);
      debugPrint('[widget] parsed nav=${tap?.nav} day=${tap?.day}');
      if (tap == null) return;
      switch (tap.nav) {
        case WeekWidgetNav.today:
          await _openWeekCalendar(DateTime.now());
        case WeekWidgetNav.day:
          await _openWeekCalendar(tap.day ?? DateTime.now());
        case WeekWidgetNav.prev:
          try {
            final shifted = await ref
                .read(homeWidgetDataBinderProvider)
                .shiftWeekWidgetAnchor(-1);
            debugPrint('[widget] shifted prev=$shifted');
            if (mounted) await _openWeekCalendar(shifted);
          } catch (e) {
            debugPrint('[widget] shift prev failed: $e');
          }
        case WeekWidgetNav.next:
          try {
            final shifted = await ref
                .read(homeWidgetDataBinderProvider)
                .shiftWeekWidgetAnchor(1);
            debugPrint('[widget] shifted next=$shifted');
            if (mounted) await _openWeekCalendar(shifted);
          } catch (e) {
            debugPrint('[widget] shift next failed: $e');
          }
      }
    } finally {
      _handlingWidgetAction = false;
      // Allow the same logical action string later (e.g. repeated taps
      // across separate resume events) once this handling completes.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handledWidgetAction = null;
      });
    }
  }

  /// Opens the app on the seven-day timeline containing [day], anchored at
  /// the configured first day of the week.
  Future<void> _openWeekCalendar(DateTime day) async {
    if (!mounted) return;
    await _onTabSelected(AppSection.calendar.index);
    if (!mounted) return;
    var firstDay = DateTime.monday;
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      firstDay = repo.weekStart;
    } catch (_) {}
    final start = weekStartFor(day, weekStartDay: firstDay);
    final notifier = ref.read(calendarStateProvider.notifier);
    notifier.goTo(start);
    notifier.setView(CalendarViewKind.multiDay, dayCount: 7);
  }

  Future<void> _restoreSession() async {
    try {
      String? startupWidgetAction;
      try {
        startupWidgetAction = await _startupWidgetActionFuture;
      } catch (_) {}
      if (!mounted) return;
      final widgetOverridesRestore = widgetActionOverridesRestore(
        startupWidgetAction,
      );
      final widgetOverridesCalendar = widgetActionTargetsCalendar(
        startupWidgetAction,
      );
      if (startupWidgetAction != null) {
        _pendingWidgetAction = startupWidgetAction;
      }
      final repo = await ref.read(settingsRepositoryProvider.future);
      if (!mounted) return;
      // Last tab. A widget tap that targets the calendar wins over restore.
      if (!widgetOverridesCalendar) {
        final idx = repo.lastTabIndex.clamp(0, 6);
        if (idx != widget.navigationShell.currentIndex) {
          widget.navigationShell.goBranch(idx);
        }
      }
      // Calendar view + anchor + day count. This is the only restore step
      // the calendar needs before its first cache build.
      if (!widgetOverridesCalendar) {
        try {
          final view = CalendarViewKind.values.firstWhere(
            (v) => v.name == repo.calendarView,
            orElse: () => CalendarViewKind.month,
          );
          final anchorMs = repo.calendarAnchorMs;
          final anchor = anchorMs == null
              ? DateTime.now()
              : DateTime.fromMillisecondsSinceEpoch(
                  anchorMs,
                  isUtc: true,
                ).toLocal();
          ref
              .read(calendarStateProvider.notifier)
              .restore(view, anchor, dayCount: repo.calendarDayCount);
        } catch (_) {}
      }
      ref.read(initialRestoreDoneProvider.notifier).markDone();
      // Drop expired drafts from previous sessions. Not needed for the
      // first calendar frame, so it runs after the restore flag is set.
      try {
        await ref.read(draftStoreProvider).clearExpired();
      } catch (_) {}
      if (!mounted) return;
      // Task list + notes folder + search filters.
      try {
        ref
            .read(selectedTaskListProvider.notifier)
            .select(repo.selectedTaskListId);
      } catch (_) {}
      try {
        ref
            .read(selectedFolderProvider.notifier)
            .select(repo.selectedNotesFolderId);
      } catch (_) {}
      try {
        if (repo.searchQuery.isNotEmpty) {
          ref.read(searchQueryProvider.notifier).set(repo.searchQuery);
        }
        final scope = SearchScope.values.firstWhere(
          (s) => s.name == repo.searchScope,
          orElse: () => SearchScope.all,
        );
        ref.read(searchScopeProvider.notifier).set(scope);
      } catch (_) {}
      // Restore a previous Google sign-in so sync works after restart.
      await ref.read(googleAccountProvider.notifier).restore();
      if (!mounted) return;
      // A widget tap requested explicit navigation; do not push restored
      // routes or reopen sheets over it.
      if (!widgetOverridesRestore) {
        // Pushed routes (search/settings) recorded before the kill.
        final route = repo.lastRoute;
        if (route == '/search' ||
            route == '/settings' ||
            route == '/alarm-settings') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            try {
              GoRouter.of(context).push(route!);
            } catch (_) {}
          });
        } else if (route != null && route.startsWith('note:')) {
          // Note editors reopen through the openSheet path below.
        }
        // Reopen the sheet/modal that was open at kill time.
        final sheet = repo.openSheet;
        if (sheet != null && sheet.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _maybeReopenSheet(sheet);
          });
        }
      }
    } catch (_) {
      // Best-effort: restore must never block startup.
      ref.read(initialRestoreDoneProvider.notifier).markDone();
      try {
        await ref.read(googleAccountProvider.notifier).restore();
      } catch (_) {}
    }
  }

  /// Reopens [sheet] (`quick_add`, `task_new`, `task:<id>`, ...).
  /// Fresh drafts (<24 h) reopen silently; week-old drafts show a
  /// "Restore draft?" banner; expired drafts are discarded.
  Future<void> _maybeReopenSheet(String sheet) async {
    if (!mounted) return;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    try {
      final settings = await ref.read(settingsRepositoryProvider.future);
      final store = ref.read(draftStoreProvider);
      final atMs = settings.openSheetAtMs ?? now;

      Future<void> openWithDraft(
        String formType,
        String? entityId,
        Map<String, dynamic>? draft,
      ) async {
        if (!mounted) return;
        await _openSheetByType(sheet, draft);
      }

      // Sheets without a draft row (details views, notes persist in DB).
      if (sheet.startsWith('event_details:') || sheet.startsWith('note:')) {
        if (now - atMs > draftExpiryMs) {
          await settings.setOpenSheet(null);
          return;
        }
        if (now - atMs > silentRestoreWindowMs) {
          _askRestoreBanner(
            sheet,
            onRestore: () => _openSheetByType(sheet, null),
          );
          return;
        }
        await _openSheetByType(sheet, null);
        return;
      }

      final parts = sheet.split(':');
      final formType = parts[0] == 'task_new'
          ? 'task'
          : parts[0] == 'event_new'
          ? 'event'
          : parts[0] == 'habit_new'
          ? 'habit'
          : parts[0] == 'countdown_new'
          ? 'countdown'
          : parts[0];
      String? entityId;
      if (sheet == 'quick_add') {
        entityId = null;
      } else if (parts.length > 1 &&
          (parts[0] == 'task' ||
              parts[0] == 'event' ||
              parts[0] == 'habit' ||
              parts[0] == 'countdown')) {
        entityId = parts.sublist(1).join(':');
      } else if (sheet.endsWith('_new')) {
        entityId = 'new';
      } else {
        return;
      }
      final draft = await store.load(formType, entityId);
      if (draft == null) {
        // No unsaved content: nothing to reopen, clear the stale marker.
        if (settings.openSheet == sheet) await settings.setOpenSheet(null);
        return;
      }
      if (draftIsExpired(draft.updatedAtMs, now)) {
        await store.clear(formType, entityId);
        if (settings.openSheet == sheet) await settings.setOpenSheet(null);
        return;
      }
      if (draftNeedsConfirm(draft.updatedAtMs, now)) {
        _askRestoreBanner(
          sheet,
          onRestore: () => openWithDraft(formType, entityId, draft.json),
        );
        return;
      }
      await openWithDraft(formType, entityId, draft.json);
    } catch (_) {}
  }

  void _askRestoreBanner(
    String sheet, {
    required Future<void> Function() onRestore,
  }) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Restore unsaved draft?'),
        duration: const Duration(seconds: 12),
        action: SnackBarAction(label: 'Restore', onPressed: () => onRestore()),
      ),
    );
    // The draft is kept until the user opens the form (which preloads it)
    // or saves. Clearing a form field deletes its draft via the autosaver,
    // and drafts expire after 7 days. The marker is cleared so this banner
    // shows at most once per restart.
    Future.microtask(() async {
      try {
        final s = await ref.read(settingsRepositoryProvider.future);
        if (s.openSheet == sheet) await s.setOpenSheet(null);
      } catch (_) {}
    });
  }

  /// Opens a sheet by its persisted descriptor. Returns false when the
  /// backing entity no longer exists (draft is cleared by the caller).
  Future<void> _openSheetByType(
    String sheet,
    Map<String, dynamic>? draft,
  ) async {
    if (!mounted) return;
    try {
      if (sheet == 'quick_add') {
        if (!mounted) return;
        await showQuickAdd(context, restoredDraft: draft);
      } else if (sheet == 'task_new') {
        if (!mounted) return;
        await showTaskEditor(context, restoredDraft: draft);
      } else if (sheet.startsWith('task:')) {
        final id = sheet.substring('task:'.length);
        final task = await _loadTask(id);
        if (task == null || !mounted) return;
        await showTaskEditor(context, task: task, restoredDraft: draft);
      } else if (sheet == 'event_new') {
        if (!mounted) return;
        await showEventEditor(context, restoredDraft: draft);
      } else if (sheet.startsWith('event:')) {
        final id = sheet.substring('event:'.length);
        final event = await _loadEvent(id);
        if (event == null || !mounted) return;
        await showEventEditor(context, event: event, restoredDraft: draft);
      } else if (sheet.startsWith('event_details:')) {
        final id = sheet.substring('event_details:'.length);
        if (!mounted) return;
        await showEventDetails(context, id);
      } else if (sheet == 'habit_new') {
        if (!mounted) return;
        await showHabitEditor(context, restoredDraft: draft);
      } else if (sheet.startsWith('habit:')) {
        final id = sheet.substring('habit:'.length);
        final habit = await _loadHabit(id);
        if (habit == null || !mounted) return;
        await showHabitEditor(context, habit: habit, restoredDraft: draft);
      } else if (sheet == 'countdown_new') {
        if (!mounted) return;
        await showCountdownEditor(context, restoredDraft: draft);
      } else if (sheet.startsWith('countdown:')) {
        final id = sheet.substring('countdown:'.length);
        final countdown = await _loadCountdown(id);
        if (countdown == null || !mounted) return;
        await showCountdownEditor(
          context,
          countdown: countdown,
          restoredDraft: draft,
        );
      } else if (sheet.startsWith('note:')) {
        final id = sheet.substring('note:'.length);
        final exists = await _noteExists(id);
        if (!exists || !mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(noteId: id)),
        );
      }
    } catch (_) {}
  }

  Future<Task?> _loadTask(String id) async {
    try {
      final db = ref.read(appDatabaseProvider);
      return await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
    } catch (_) {
      return null;
    }
  }

  Future<Event?> _loadEvent(String id) async {
    try {
      final rows =
          await (ref.read(eventRepositoryProvider).dbSelect()
                ..where((e) => e.id.equals(id)))
              .getSingleOrNull();
      return rows;
    } catch (_) {
      return null;
    }
  }

  Future<Habit?> _loadHabit(String id) async {
    try {
      final db = ref.read(appDatabaseProvider);
      return await (db.select(
        db.habits,
      )..where((h) => h.id.equals(id))).getSingleOrNull();
    } catch (_) {
      return null;
    }
  }

  Future<Countdown?> _loadCountdown(String id) async {
    try {
      final db = ref.read(appDatabaseProvider);
      return await (db.select(
        db.countdowns,
      )..where((c) => c.id.equals(id))).getSingleOrNull();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _noteExists(String id) async {
    try {
      return await ref.read(noteRepositoryProvider).getNote(id) != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> _onTabSelected(int branchIndex) async {
    widget.navigationShell.goBranch(branchIndex);
    if (branchIndex == AppSection.calendar.index) {
      ref.read(timelineNowControllerProvider).refresh();
    }
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      await repo.setLastTabIndex(branchIndex);
      await repo.setLastRoute('/tab$branchIndex');
    } catch (_) {}
  }

  bool _isEditingText() {
    final node = FocusManager.instance.primaryFocus;
    final ctx = node?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    if (ctx.findAncestorWidgetOfExactType<EditableText>() != null) return true;
    return false;
  }

  bool _handleGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (_isEditingText()) return false;
    var handled = false;
    for (final activator in _shortcuts.keys) {
      if (activator.accepts(event, HardwareKeyboard.instance)) {
        _shortcuts[activator]!();
        handled = true;
      }
    }
    return handled;
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

    final shortcuts = <ShortcutActivator, VoidCallback>{
      SingleActivator(LogicalKeyboardKey.keyN): () {
        if (!mounted) return;
        showQuickAdd(context);
      },
      SingleActivator(LogicalKeyboardKey.keyT): () {
        if (!mounted) return;
        _onTabSelected(AppSection.calendar.index);
        try {
          ref.read(calendarStateProvider.notifier).goToday();
        } catch (_) {}
      },
      SingleActivator(LogicalKeyboardKey.slash): () {
        if (!mounted) return;
        context.push('/search');
        Future.microtask(() async {
          try {
            final repo = await ref.read(settingsRepositoryProvider.future);
            await repo.setLastRoute('/search');
          } catch (_) {}
        });
      },
      SingleActivator(LogicalKeyboardKey.escape): () {
        if (!mounted) return;
        final nav = Navigator.of(context);
        if (nav.canPop()) nav.pop();
      },
      SingleActivator(LogicalKeyboardKey.arrowLeft): () {
        if (!mounted) return;
        if (widget.navigationShell.currentIndex != AppSection.calendar.index) {
          return;
        }
        final w = ref.read(calendarStateProvider);
        final step = switch (w.view) {
          CalendarViewKind.month => 30,
          CalendarViewKind.year => 365,
          CalendarViewKind.multiDay => w.dayCount,
          _ => 1,
        };
        ref.read(calendarStateProvider.notifier).shift(-step);
      },
      SingleActivator(LogicalKeyboardKey.arrowRight): () {
        if (!mounted) return;
        if (widget.navigationShell.currentIndex != AppSection.calendar.index) {
          return;
        }
        final w = ref.read(calendarStateProvider);
        final step = switch (w.view) {
          CalendarViewKind.month => 30,
          CalendarViewKind.year => 365,
          CalendarViewKind.multiDay => w.dayCount,
          _ => 1,
        };
        ref.read(calendarStateProvider.notifier).shift(step);
      },
      for (var i = 0; i < AppSection.values.length; i++)
        SingleActivator(_digitKeys[i]): () {
          if (!mounted) return;
          _onTabSelected(i);
        },
    };

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
    );
  }

  void _showMore(BuildContext context, List<int> more, List<int> order) {
    showAppSheet<void>(
      context,
      builder: (ctx) => EscapeToClose(
        child: MoreSheet(
          more: more,
          onSelected: (idx) {
            Navigator.of(ctx).pop();
            _onTabSelected(idx);
          },
          onReorder: () async {
            Navigator.of(ctx).pop();
            await _reorderSheet(context, order);
          },
        ),
      ),
    );
  }

  Future<void> _reorderSheet(BuildContext context, List<int> order) async {
    final current = List<int>.from(order);
    await showAppSheet<void>(
      context,
      builder: (ctx) => EscapeToClose(
        child: StatefulBuilder(
          builder: (ctx, setSt) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Reorder sections',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                  ),
                  Flexible(
                    child: ReorderableListView(
                      shrinkWrap: true,
                      onReorderItem: (oldIndex, newIndex) {
                        setSt(() {
                          final item = current.removeAt(oldIndex);
                          current.insert(newIndex, item);
                        });
                      },
                      children: [
                        for (final idx in current)
                          ListTile(
                            key: ValueKey(idx),
                            leading: Icon(AppSection.values[idx].icon),
                            title: Text(AppSection.values[idx].title),
                            trailing: const Icon(Icons.drag_handle),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      onPressed: () async {
                        final repo = await ref.read(
                          settingsRepositoryProvider.future,
                        );
                        await repo.setNavOrder(current);
                        ref.invalidate(settingsRepositoryProvider);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      },
                      child: const Text('Save'),
                    ),
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
