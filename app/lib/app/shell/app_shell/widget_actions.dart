part of '../app_shell.dart';

extension _AppShellWidgetActions on _AppShellState {
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
}
