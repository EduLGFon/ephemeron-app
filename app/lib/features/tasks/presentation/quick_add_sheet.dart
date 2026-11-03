// Quick-add bottom sheet: one field with shorthand and NLP parsing,
// live preview chips, save and save-and-add-another.
// Unsaved text autosaves (debounced) and restores after restart.
import 'package:flutter/material.dart';
import 'package:ephemeron/core/time/device_date_format.dart';
import 'package:ephemeron/core/ui/app_sheet.dart';
import 'package:ephemeron/core/ui/sheet_padding.dart';
import 'package:ephemeron/core/ui/escape_to_close.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/session/session_restore.dart';
import '../../../domain/parsing/quick_add_parser.dart';
import '../../settings/application/settings_providers.dart';
import '../application/tasks_providers.dart';

Future<void> showQuickAdd(
  BuildContext context, {
  String? initialText,
  Map<String, dynamic>? restoredDraft,
}) {
  return showAppSheet<void>(
    context,
    builder: (_) => EscapeToClose(
      child: _QuickAddSheet(
        initialText: initialText,
        restoredDraft: restoredDraft,
      ),
    ),
  );
}

class _QuickAddSheet extends ConsumerStatefulWidget {
  const _QuickAddSheet({this.initialText, this.restoredDraft});

  final String? initialText;
  final Map<String, dynamic>? restoredDraft;

  @override
  ConsumerState<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<_QuickAddSheet> {
  final _controller = TextEditingController();
  QuickAddParsed? _parsed;
  DraftAutosaver? _saver;
  bool _saved = false;
  dynamic _settings;

  @override
  void initState() {
    super.initState();
    final restored = widget.restoredDraft?['text'] as String?;
    final initial = widget.initialText ?? restored ?? '';
    if (initial.isNotEmpty) {
      _controller.text = initial;
      _parsed = parseQuickAdd(initial);
    }
    if (restored == null) {
      // Preload a leftover draft for fresh opens (e.g. dismissed sheet).
      Future.microtask(_preloadDraft);
    }
  }

  Future<void> _preloadDraft() async {
    if (!mounted || _controller.text.isNotEmpty) return;
    try {
      final draft = await ref.read(draftStoreProvider).load('quick_add', null);
      if (draft == null || !mounted || _controller.text.isNotEmpty) return;
      final text = draft.json['text'] as String?;
      if (text == null || text.isEmpty) return;
      if (draftIsExpired(
        draft.updatedAtMs,
        DateTime.now().toUtc().millisecondsSinceEpoch,
      )) {
        return;
      }
      setState(() {
        _controller.text = text;
        _parsed = parseQuickAdd(text);
      });
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _saver ??= DraftAutosaver(ref.read(draftStoreProvider), 'quick_add', null);
    // Track the open sheet so a kill mid-typing restores it.
    // (dispose never runs on process kill, so the value survives kills
    // but is cleared on normal close in dispose below.)
    Future.microtask(() async {
      try {
        final repo = await ref.read(settingsRepositoryProvider.future);
        _settings = repo;
        await repo.setOpenSheet('quick_add');
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    if (!_saved) {
      _saver?.changed(() => {'text': _controller.text});
    }
    _saver?.dispose();
    final settings = _settings;
    // Normal close: clear the marker but keep the draft for preload.
    // Process kill skips dispose, so the marker survives kills.
    if (settings != null) {
      Future.microtask(() async {
        try {
          if (settings.openSheet == 'quick_add') {
            await settings.setOpenSheet(null);
          }
        } catch (_) {}
      });
    }
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() {
      _parsed = v.trim().isEmpty ? null : parseQuickAdd(v);
    });
    _saver?.changed(() => {'text': v});
  }

  Future<void> _save({required bool another}) async {
    final p = _parsed;
    if (p == null || p.title.isEmpty) return;
    final repo = ref.read(taskRepositoryProvider);
    String? listId;
    if (p.list != null) {
      final lists = await ref.read(taskListsProvider.future);
      listId = lists
          .where((l) => l.name.toLowerCase() == p.list!.toLowerCase())
          .map((l) => l.id)
          .firstOrNull;
      listId ??= await repo.createList(p.list!);
    }
    await repo.createTask(
      title: p.title,
      listId: listId,
      priority: p.priority,
      dueDate: p.due == null
          ? null
          : '${p.due!.year.toString().padLeft(4, '0')}-'
                '${p.due!.month.toString().padLeft(2, '0')}-'
                '${p.due!.day.toString().padLeft(2, '0')}',
      dueTime: p.due == null || (p.due!.hour == 0 && p.due!.minute == 0)
          ? null
          : p.due!.hour * 60 + p.due!.minute,
      rrule: p.rrule,
      tags: p.tags,
    );
    if (!mounted) return;
    try {
      ref.read(occurrenceDirtyProvider.notifier).markDirty();
    } catch (_) {}
    _saved = true;
    try {
      await ref.read(draftStoreProvider).clear('quick_add', null);
      final srepo = await ref.read(settingsRepositoryProvider.future);
      if (srepo.openSheet == 'quick_add') await srepo.setOpenSheet(null);
    } catch (_) {}
    if (!mounted) return;
    if (another) {
      _saved = false;
      _controller.clear();
      setState(() => _parsed = null);
    } else {
      final nav = Navigator.of(context);
      if (nav.canPop()) nav.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _parsed;
    return SafeArea(
      child: Padding(
        padding: sheetPadding(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Buy milk #groceries ~home -p1 tomorrow 9h',
                border: OutlineInputBorder(),
              ),
              onChanged: _onChanged,
              onSubmitted: (_) => _save(another: false),
            ),
            if (p != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  Chip(label: Text(p.title)),
                  for (final t in p.tags) Chip(label: Text('#$t')),
                  if (p.list != null) Chip(label: Text('~${p.list}')),
                  if (p.priority > 0) Chip(label: Text('P${5 - p.priority}')),
                  if (p.due != null)
                    Chip(
                      label: Text(
                        DeviceDateFormat.yMMMd(context).add_Hm().format(p.due!),
                      ),
                    ),
                  if (p.rrule != null) Chip(label: Text(p.rrule!)),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: p == null ? null : () => _save(another: false),
                    child: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: p == null ? null : () => _save(another: true),
                  child: const Text('Save + another'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
