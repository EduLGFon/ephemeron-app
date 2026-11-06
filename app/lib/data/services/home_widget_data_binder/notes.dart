part of '../home_widget_data_binder.dart';

extension HomeWidgetDataBinderNotes on HomeWidgetDataBinder {
  Future<void> _refreshNotes() async {
    try {
      final repo = ref.read(noteRepositoryProvider);
      final notes = await repo.watchNotesInFolder(null).first;
      final pinnedId =
          await _config('OneNoteWidgetProvider') ??
          await _config('PinnedNoteWidgetProvider');
      final shown = pinnedId == null
          ? (notes.isEmpty ? null : notes.first)
          : await repo.getNote(pinnedId);
      if (shown != null) {
        await _svc.update(
          keyPrefix: 'one_note',
          provider: 'OneNoteWidgetProvider',
          title: shown.title,
          body: (shown.body?.length ?? 0) > 120
              ? shown.body!.substring(0, 120)
              : shown.body ?? '',
        );
        _mark('one_note');
      }
      await _svc.updateCollection(
        keyPrefix: 'recent_notes_collection',
        provider: 'RecentNotesCollectionProvider',
        title: 'Recent notes',
        items: notes
            .take(5)
            .map((n) => {'id': n.id, 'title': n.title})
            .toList(),
      );
      _mark('recent_notes_collection');
    } catch (_) {}
  }
}
