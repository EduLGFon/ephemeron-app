part of '../app_shell.dart';

const List<LogicalKeyboardKey> _digitKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
];

extension _AppShellShortcuts on _AppShellState {
  /// Keyboard shortcuts active on every route. Rebuilt with [build] so the
  /// callbacks always see the current widget/riverpod state.
  Map<ShortcutActivator, VoidCallback> _buildShortcuts() {
    return <ShortcutActivator, VoidCallback>{
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
}
