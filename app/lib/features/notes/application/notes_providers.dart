// Riverpod providers for notes. UI reads only from Drift streams.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/db_provider.dart';
import '../../../data/drift/app_database.dart';
import '../../../data/repositories/note_repository.dart';

final noteRepositoryProvider = Provider<NoteRepository>((ref) {
  return NoteRepository(ref.watch(appDatabaseProvider));
});

final foldersProvider = StreamProvider.family<List<Folder>, String?>((
  ref,
  parentId,
) {
  return ref.watch(noteRepositoryProvider).watchChildFolders(parentId);
});

final folderNotesProvider = StreamProvider.family<List<Note>, String?>((
  ref,
  folderId,
) {
  return ref.watch(noteRepositoryProvider).watchNotesInFolder(folderId);
});

final noteTrashProvider = StreamProvider<List<Note>>((ref) {
  return ref.watch(noteRepositoryProvider).watchTrash();
});

/// Null means the top level (unfiled notes).
final selectedFolderProvider = NotifierProvider<SelectedFolder, String?>(
  SelectedFolder.new,
);

class SelectedFolder extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}
