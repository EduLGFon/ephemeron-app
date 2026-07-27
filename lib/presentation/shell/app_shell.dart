import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/settings/app_settings_provider.dart';
import '../../core/settings/power_saving_manager.dart';
import '../../core/theme/theme_engine_provider.dart';

import '../../data/local/database.dart';
import '../../data/local/database_provider.dart';
import '../../features/calendar/application/calendar_providers.dart';
import '../../features/calendar/presentation/event_form_sheet.dart';
import '../../features/countdown/domain/countdown_type.dart';
import '../../features/countdown/presentation/countdown_form_sheet.dart';
import '../../features/habits/presentation/habit_form_sheet.dart';
import '../../features/quick_add/application/quick_add_provider.dart';
import '../../features/quick_add/presentation/unified_creation_sheet.dart';

import '../../features/tasks/presentation/task_form_sheet.dart';
import '../notes/note_form_sheet.dart';
import '../widgets/keyboard_avoid_padding.dart';

import 'pinned_sections_provider.dart';
import 'premium_navigation_bar.dart';
import 'quick_add_pill.dart';
import 'overflow_sheet.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _sectionsWithQuickAdd = {0, 1, 2, 3, 4, 6}; // Removed 5 (Focus)

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();

      // 1. Restore last screen if different from current branch
      final lastScreen = prefs.getString('settings.lastScreen');
      if (lastScreen != null) {
        final paths = [
          '/calendar',
          '/tasks',
          '/matrix',
          '/habits',
          '/countdown',
          '/focus',
          '/notes'
        ];
        final targetIndex = paths.indexOf(lastScreen);
        if (targetIndex != -1 &&
            targetIndex != widget.navigationShell.currentIndex) {
          widget.navigationShell.goBranch(targetIndex);
        }
      }

      // 2. Restore open menu (deferred)
      Future.delayed(const Duration(seconds: 2), () async {
        if (!mounted) return;
        final menu = prefs.getString('session.openMenu') ?? 'none';
        if (menu == 'none') return;

        // Clear it so it doesn't loop
        await prefs.setString('session.openMenu', 'none');

        final entityId = prefs.getString('session.openMenuEntityId') ?? '';
        final extra = prefs.getString('session.openMenuExtra') ?? '';

        if (!mounted) return;

        if (menu == 'quick_add') {
          unawaited(showUnifiedCreationSheet(context));
        } else if (menu == 'task') {
          if (entityId.isNotEmpty) {
            final db = ref.read(appDatabaseProvider);
            final task = await (db.select(db.tasks)
                  ..where((t) => t.id.equals(entityId)))
                .getSingleOrNull();
            if (task != null && mounted) {
              unawaited(showTaskFormSheet(context,
                  listId: extra, existingTask: task));
            }
          } else {
            unawaited(showTaskFormSheet(context, listId: extra));
          }
        } else if (menu == 'event') {
          if (entityId.isNotEmpty) {
            final repo = ref.read(calendarRepositoryProvider);
            final event = await repo.getEvent('primary', entityId);
            if (event != null && mounted) {
              unawaited(showEventFormSheet(context,
                  initialDay: event.start, existingEvent: event));
            }
          } else {
            final day = DateTime.tryParse(extra) ?? DateTime.now();
            unawaited(showEventFormSheet(context, initialDay: day));
          }
        } else if (menu == 'habit') {
          if (entityId.isNotEmpty) {
            final db = ref.read(appDatabaseProvider);
            final habit = await (db.select(db.habits)
                  ..where((h) => h.id.equals(entityId)))
                .getSingleOrNull();
            if (habit != null && mounted) {
              unawaited(showHabitFormSheet(context, existingHabit: habit));
            }
          } else {
            unawaited(showHabitFormSheet(context));
          }
        } else if (menu == 'countdown') {
          final type = CountdownType.values.firstWhere((t) => t.name == extra,
              orElse: () => CountdownType.custom);
          if (entityId.isNotEmpty) {
            final db = ref.read(appDatabaseProvider);
            final cd = await (db.select(db.countdowns)
                  ..where((c) => c.id.equals(entityId)))
                .getSingleOrNull();
            if (cd != null && mounted) {
              unawaited(showCountdownFormSheet(context,
                  type: type, existingCountdown: cd));
            }
          } else {
            unawaited(showCountdownFormSheet(context, type: type));
          }
        } else if (menu == 'note') {
          if (entityId.isNotEmpty) {
            final db = ref.read(appDatabaseProvider);
            final note = await (db.select(db.notes)
                  ..where((n) => n.id.equals(entityId)))
                .getSingleOrNull();
            if (note != null && mounted) {
              _showNoteFormSheet(context, note);
            }
          } else {
            _showNoteFormSheet(context, null);
          }
        }
      });
    });
  }

  void _showNoteFormSheet(BuildContext context, Note? existingNote) {
    final sheet = Center(
      child: SingleChildScrollView(
        child: Material(
          color: Colors.transparent,
          child:
              RepaintBoundary(child: NoteFormSheet(existingNote: existingNote)),
        ),
      ),
    );

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) {
        return KeyboardAvoidPadding(child: sheet);
      },
      transitionBuilder: (context, anim1, anim2, child) {
        final curve =
            CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, 1.0),
            end: Offset.zero,
          ).animate(curve),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pinned = ref.watch(pinnedSectionsProvider);
    final overflow = ref.watch(overflowSectionsProvider);
    final settings = ref.watch(appSettingsProvider);
    final palette = ref.watch(themeEngineProvider);

    final currentPinnedIndex = pinned.indexWhere(
      (s) => s.branchIndex == widget.navigationShell.currentIndex,
    );
    final selectedIndex =
        currentPinnedIndex == -1 ? pinned.length : currentPinnedIndex;
    final showQuickAdd =
        _sectionsWithQuickAdd.contains(widget.navigationShell.currentIndex);
    ref.listen<QuickAddData>(quickAddProvider, (prev, next) {
      if (next.state == QuickAddState.expanded &&
          (prev == null || prev.state != QuickAddState.expanded)) {
        final currentSection = pinned.firstWhere(
          (s) => s.branchIndex == widget.navigationShell.currentIndex,
          orElse: () => overflow.firstWhere(
            (s) => s.branchIndex == widget.navigationShell.currentIndex,
          ),
        );
        showUnifiedCreationSheet(context,
                currentSection: currentSection, entity: next.entity)
            .then((_) {
          if (mounted) {
            ref.read(quickAddProvider.notifier).close();
          }
        });
      }
    });

    ref.listen<bool>(lowBatteryWarningProvider, (prev, next) {
      if (next && !(prev ?? false)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Battery is low (<15%). Consider manually enabling Power Saving Mode.'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    });

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      extendBody: false,
      body: widget.navigationShell,
      floatingActionButton: showQuickAdd
          ? QuickAddPill(
              currentSection: pinned.firstWhere(
                (s) => s.branchIndex == widget.navigationShell.currentIndex,
                orElse: () => overflow.firstWhere(
                  (s) => s.branchIndex == widget.navigationShell.currentIndex,
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: const KeyboardAttachedFabLocation(),
      bottomNavigationBar: PremiumNavigationBar(
        isPill: settings.usePillNavigation,
        pinned: pinned,
        selectedIndex: selectedIndex,
        palette: palette,
        onDestinationSelected: (index) {
          if (index < pinned.length) {
            widget.navigationShell.goBranch(
              pinned[index].branchIndex,
              initialLocation: pinned[index].branchIndex ==
                  widget.navigationShell.currentIndex,
            );
          } else {
            showOverflowSheet(
                context, ref, overflow, widget.navigationShell, palette);
          }
        },
      ),
    );
  }
}
