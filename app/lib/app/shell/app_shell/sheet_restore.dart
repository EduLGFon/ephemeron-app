part of '../app_shell.dart';

extension _AppShellSheetRestore on _AppShellState {
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
}
