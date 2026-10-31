import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/system_launcher.dart';
import '../../features/alarms/application/alarm_providers.dart';
import '../../features/alarms/data/fallback_alarm_engine.dart';
import '../../features/auth/application/auth_providers.dart';
import '../../features/calendar/application/calendar_providers.dart';
import '../../features/calendar/application/calendar_state.dart';
import '../../features/settings/application/settings_providers.dart';
import '../../features/settings/presentation/onboarding_screen.dart';
import '../../features/sync/application/sync_providers.dart';
import '../../features/tasks/presentation/quick_add_sheet.dart';
import 'app_sections.dart';
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

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    _restoreLastTab();
    // Restart the persisted auto-sync schedule on every launch.
    Future.microtask(() => ref.read(googleAutoSyncServiceProvider).start());
    Future.microtask(
      () => ref.read(backendAutoSyncServiceProvider).reschedule(),
    );
    // Rebuild the alarm window on every app open (rolling 48 h + 60).
    Future.microtask(() async {
      try {
        await ref.read(alarmRepositoryProvider).rebuildWindow();
      } catch (_) {}
    });
    // Handle Android share-target text and launcher shortcuts once the
    // first frame is up (needs a BuildContext for sheets/navigation).
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleIntents());
  }

  /// Opens quick add prefilled with shared text, or jumps to the tab
  /// requested by a launcher shortcut. No-ops on other platforms.
  Future<void> _handleIntents() async {
    if (!mounted) return;
    final shared = await SystemLauncher.consumeSharedText();
    if (shared != null && shared.trim().isNotEmpty && mounted) {
      await showQuickAdd(context, initialText: shared.trim());
    }
    if (!mounted) return;
    final action = await SystemLauncher.consumeLaunchAction();
    if (action == null || !mounted) return;
    switch (action) {
      case 'new_task':
        await showQuickAdd(context);
      case 'new_event':
        _onTabSelected(AppSection.calendar.index);
      case 'start_focus':
        _onTabSelected(AppSection.focus.index);
    }
  }

  Future<void> _restoreLastTab() async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    if (!mounted) return;
    final idx = repo.lastTabIndex.clamp(0, 6);
    if (idx != widget.navigationShell.currentIndex) {
      widget.navigationShell.goBranch(idx);
    }
    // Restore a previous Google sign-in so sync works after restart.
    await ref.read(googleAccountProvider.notifier).restore();
  }

  Future<void> _onTabSelected(int branchIndex) async {
    widget.navigationShell.goBranch(branchIndex);
    final repo = await ref.read(settingsRepositoryProvider.future);
    await repo.setLastTabIndex(branchIndex);
  }

  @override
  Widget build(BuildContext context) {
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

    return CallbackShortcuts(
      bindings: shortcuts,
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
      ), // AlarmListener
    ); // CallbackShortcuts
  }

  void _showMore(BuildContext context, List<int> more, List<int> order) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => MoreSheet(
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
    );
  }

  Future<void> _reorderSheet(BuildContext context, List<int> order) async {
    final current = List<int>.from(order);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Reorder sections',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                Expanded(
                  child: ReorderableListView(
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
    );
  }
}
