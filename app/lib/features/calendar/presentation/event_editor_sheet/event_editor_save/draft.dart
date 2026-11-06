part of '../../event_editor_sheet.dart';

extension on _EventEditorState {
  Future<void> _clearDraftAfterSave() async {
    _saved = true;
    try {
      await ref.read(draftStoreProvider).clear('event', _draftEntityId);
      final srepo = await ref.read(settingsRepositoryProvider.future);
      final expected = widget.event == null
          ? 'event_new'
          : 'event:${widget.event!.id}';
      if (srepo.openSheet == expected) await srepo.setOpenSheet(null);
    } catch (_) {}
  }

  /// Trims the description and caps the event column at 8000 chars so the
  /// full text can live in a linked overflow note.
  ({String? full, String? stored}) _notesPayload() {
    final full = _notes.text.trim();
    if (full.isEmpty) return (full: null, stored: null);
    return (
      full: full,
      stored: full.length > 8000
          ? '${full.substring(0, 8000)}\n(continued in Ephemeron)'
          : full,
    );
  }

  Future<void> _persistOverflow(String eventId, String? fullNotes) async {
    if (fullNotes == null || fullNotes.length <= 8000) return;
    final noteId = await ref
        .read(noteRepositoryProvider)
        .ensureOverflowNote(eventId, fullNotes);
    await ref.read(eventRepositoryProvider).setNotesOverflow(eventId, noteId);
  }
}
