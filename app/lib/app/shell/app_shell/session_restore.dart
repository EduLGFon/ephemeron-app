part of '../app_shell.dart';

extension _AppShellSessionRestore on _AppShellState {
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
}
