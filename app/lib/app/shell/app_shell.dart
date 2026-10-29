import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/settings/application/settings_providers.dart';
import '../../features/settings/presentation/onboarding_screen.dart';
import 'app_sections.dart';

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
  }

  Future<void> _restoreLastTab() async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    if (!mounted) return;
    final idx = repo.lastTabIndex.clamp(0, 6);
    if (idx != widget.navigationShell.currentIndex) {
      widget.navigationShell.goBranch(idx);
    }
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

    return Scaffold(
      extendBody: true,
      body: widget.navigationShell,
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: NavigationBar(
          selectedIndex: pinned.contains(widget.navigationShell.currentIndex)
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
    );
  }

  void _showMore(BuildContext context, List<int> more, List<int> order) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => _MoreSheet(
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

class _MoreSheet extends StatelessWidget {
  const _MoreSheet({
    required this.more,
    required this.onSelected,
    required this.onReorder,
  });

  final List<int> more;
  final ValueChanged<int> onSelected;
  final VoidCallback onReorder;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final idx in more)
            ListTile(
              leading: Icon(AppSection.values[idx].icon),
              title: Text(AppSection.values[idx].title),
              onTap: () => onSelected(idx),
            ),
          ListTile(
            leading: const Icon(Icons.search),
            title: const Text('Search'),
            onTap: () {
              Navigator.of(context).pop();
              context.push('/search');
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            onTap: () {
              Navigator.of(context).pop();
              context.push('/settings');
            },
          ),
          ListTile(
            leading: const Icon(Icons.reorder),
            title: const Text('Customize navigation'),
            onTap: onReorder,
          ),
        ],
      ),
    );
  }
}
