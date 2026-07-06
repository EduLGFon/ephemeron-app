import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/theme/theme_engine_provider.dart';
import '../../core/theme/theme_palettes.dart';
import '../../data/local/database.dart';
import '../../features/calendar/application/calendar_providers.dart';
import '../../features/calendar/presentation/event_form_sheet.dart';
import '../../features/notes/application/notes_providers.dart';
import '../../features/notes/data/notes_repository.dart';

class NoteFormSheet extends ConsumerStatefulWidget {
  const NoteFormSheet({this.existingNote, this.unifiedHeader, super.key});

  final Note? existingNote;
  final Widget? unifiedHeader;

  @override
  ConsumerState<NoteFormSheet> createState() => _NoteFormSheetState();
}

class _NoteFormSheetState extends ConsumerState<NoteFormSheet> {
  late final _titleController = TextEditingController(text: widget.existingNote?.title);
  late final _contentController = TextEditingController(text: widget.existingNote?.content);
  bool _isSaving = false;
  bool _isFullScreen = false;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(themeEngineProvider);
    final existingNote = widget.existingNote;

    // Replace "edit note" header by the note/event title
    String headerText = 'New Note';
    if (existingNote != null) {
      if (existingNote.title.isNotEmpty) {
        headerText = existingNote.title;
      } else {
        headerText = 'Untitled Note';
      }
    }

    final dialogContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.unifiedHeader != null) widget.unifiedHeader!,
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                headerText,
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: palette.text,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Full Screen button
                IconButton(
                  icon: Icon(
                    _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    color: palette.text.withValues(alpha: 0.7),
                  ),
                  tooltip: _isFullScreen ? 'Exit Full Screen' : 'Full Screen',
                  onPressed: () {
                    setState(() {
                      _isFullScreen = !_isFullScreen;
                    });
                  },
                ),
                if (existingNote != null)
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: Colors.redAccent.withValues(alpha: 0.8)),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: palette.surface,
                          title: Text('Delete note?', style: TextStyle(color: palette.text)),
                          content: Text(
                            'Are you sure you want to permanently delete this note?',
                            style: TextStyle(color: palette.text.withValues(alpha: 0.7)),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text('Cancel', style: TextStyle(color: palette.text.withValues(alpha: 0.6))),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: Colors.red),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && mounted) {
                        await ref.read(notesRepositoryProvider).deleteNote(existingNote.id);
                        if (mounted) Navigator.pop(context);
                      }
                    },
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _titleController,
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: palette.text, fontWeight: FontWeight.bold, fontSize: 18),
          decoration: InputDecoration(
            hintText: 'Title',
            hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.4)),
            border: InputBorder.none,
          ),
        ),
        const Divider(),
        Expanded(
          child: TextField(
            controller: _contentController,
            maxLines: null,
            expands: true,
            style: TextStyle(color: palette.text),
            decoration: InputDecoration(
              hintText: 'Type your note here...',
              hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.4)),
              border: InputBorder.none,
            ),
          ),
        ),
        // Event link shortcut
        if (existingNote?.eventId != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: EventShortcutChip(
              eventId: existingNote!.eventId!,
              calendarId: existingNote.linkedCalendarId ?? 'primary',
              palette: palette,
              ref: ref,
              onDismiss: () => Navigator.of(context).pop(),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: palette.text.withValues(alpha: 0.6))),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: palette.primary,
                foregroundColor: palette.background,
              ),
              onPressed: _isSaving
                  ? null
                  : () async {
                      final title = _titleController.text.trim();
                      final content = _contentController.text.trim();
                      if (title.isEmpty && content.isEmpty) return;

                      setState(() => _isSaving = true);
                      try {
                        final folderId = ref.read(currentFolderIdProvider);
                        final repo = ref.read(notesRepositoryProvider);

                        if (existingNote != null) {
                          await repo.updateNote(NotesCompanion(
                            id: Value(existingNote.id),
                            title: Value(title.isEmpty ? '(Untitled)' : title),
                            content: Value(content),
                            folderId: Value(existingNote.folderId),
                            updatedAt: Value(DateTime.now()),
                          ));
                        } else {
                          await repo.createNote(NotesCompanion.insert(
                            title: title.isEmpty ? '(Untitled)' : title,
                            content: content,
                            folderId: Value(folderId),
                          ));
                        }
                        if (mounted) Navigator.of(context).pop();
                      } finally {
                        if (mounted) setState(() => _isSaving = false);
                      }
                    },
              child: _isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save'),
            ),
          ],
        ),
      ],
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      margin: _isFullScreen ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      width: _isFullScreen ? MediaQuery.of(context).size.width : (MediaQuery.of(context).size.width * 0.9).clamp(300.0, 600.0),
      height: _isFullScreen ? MediaQuery.of(context).size.height : (MediaQuery.of(context).size.height * 0.8).clamp(400.0, 600.0),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.95),
        borderRadius: _isFullScreen ? BorderRadius.zero : BorderRadius.circular(28),
        border: _isFullScreen ? null : Border.all(color: palette.text.withValues(alpha: 0.1)),
        boxShadow: _isFullScreen
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                )
              ],
      ),
      child: ClipRRect(
        borderRadius: _isFullScreen ? BorderRadius.zero : BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: _isFullScreen
                  ? EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 16,
                      bottom: MediaQuery.of(context).padding.bottom + 16,
                      left: 24,
                      right: 24,
                    )
                  : const EdgeInsets.all(24),
              child: dialogContent,
            ),
          ),
        ),
      ),
    );
  }
}

class EventShortcutChip extends StatefulWidget {
  const EventShortcutChip({
    required this.eventId,
    required this.calendarId,
    required this.palette,
    required this.ref,
    required this.onDismiss,
    super.key,
  });

  final String eventId;
  final String calendarId;
  final AppPalette palette;
  final WidgetRef ref;
  final VoidCallback onDismiss;

  @override
  State<EventShortcutChip> createState() => _EventShortcutChipState();
}

class _EventShortcutChipState extends State<EventShortcutChip> {
  bool _loading = false;

  Future<void> _openEvent() async {
    setState(() => _loading = true);
    try {
      final repo = widget.ref.read(calendarRepositoryProvider);
      final event = await repo.getEvent(widget.calendarId, widget.eventId);
      if (!mounted) return;
      if (event == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Event not found — it may have been deleted or you\'re not signed in.')),
        );
        return;
      }
      // Dismiss note dialog first, then open the event form
      widget.onDismiss();
      if (!mounted) return;
      await showEventFormSheet(context, initialDay: event.start, existingEvent: event);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return GestureDetector(
      onTap: _loading ? null : _openEvent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: p.primary.withValues(alpha: _loading ? 0.06 : 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading)
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: p.primary),
              )
            else
              Icon(Icons.event_outlined, size: 14, color: p.primary),
            const SizedBox(width: 6),
            Text(
              _loading ? 'Loading event...' : 'Open in Calendar',
              style: TextStyle(color: p.primary, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            if (!_loading) ...[
              const SizedBox(width: 4),
              Icon(Icons.open_in_new, size: 11, color: p.primary.withValues(alpha: 0.7)),
            ],
          ],
        ),
      ),
    );
  }
}
