part of '../headless_widget_push.dart';

Future<void> pushNoteWidgets(AppDatabase db, {String? noteId}) async {
  try {
    final repo = NoteRepository(db);
    if (noteId != null) {
      final note = await repo.getNote(noteId);
      if (note != null) {
        final body = note.body ?? '';
        await _push(
          'one_note',
          'OneNoteWidgetProvider',
          note.title,
          body.length > 120 ? body.substring(0, 120) : body,
        );
        return;
      }
    }
    final notes = await repo.watchNotesInFolder(null).first;
    if (notes.isEmpty) return;
    final body = notes.first.body ?? '';
    await _push(
      'one_note',
      'OneNoteWidgetProvider',
      notes.first.title,
      body.length > 120 ? body.substring(0, 120) : body,
    );
  } catch (_) {}
}
