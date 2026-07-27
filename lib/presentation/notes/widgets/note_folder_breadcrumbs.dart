import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_palettes.dart';
import '../../../data/local/database.dart';
import '../../../features/notes/application/notes_providers.dart';
import '../../../features/notes/data/notes_repository.dart';

class NoteFolderBreadcrumbs extends ConsumerWidget {
  const NoteFolderBreadcrumbs({
    super.key,
    required this.currentId,
    required this.allFolders,
    required this.palette,
  });

  final String? currentId;
  final List<NoteFolder> allFolders;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = <Widget>[];

    // Notes root folder breadcrumb target
    path.add(
      DragTarget<Note>(
        onWillAcceptWithDetails: (details) => details.data.folderId != null,
        onAcceptWithDetails: (details) async {
          final note = details.data;
          await ref
              .read(notesRepositoryProvider)
              .moveNoteToFolder(note.id, null);
        },
        builder: (context, candidateData, rejectedData) {
          final isHovered = candidateData.isNotEmpty;
          return GestureDetector(
            onTap: () =>
                ref.read(currentFolderIdProvider.notifier).setFolder(null),
            child: Text(
              'Notes',
              style: TextStyle(
                color: isHovered
                    ? palette.primary
                    : (currentId == null
                        ? palette.text
                        : palette.text.withValues(alpha: 0.5)),
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          );
        },
      ),
    );

    if (currentId != null) {
      final list = <NoteFolder>[];
      String? targetId = currentId;
      while (targetId != null) {
        final folderList = allFolders.where((f) => f.id == targetId);
        if (folderList.isEmpty) break;
        final folder = folderList.first;
        list.insert(0, folder);
        targetId = folder.parentFolderId;
      }
      for (final folder in list) {
        path.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.chevron_right,
              color: palette.text.withValues(alpha: 0.3), size: 16),
        ));

        path.add(
          DragTarget<Note>(
            onWillAcceptWithDetails: (details) =>
                details.data.folderId != folder.id,
            onAcceptWithDetails: (details) async {
              final note = details.data;
              await ref
                  .read(notesRepositoryProvider)
                  .moveNoteToFolder(note.id, folder.id);
            },
            builder: (context, candidateData, rejectedData) {
              final isHovered = candidateData.isNotEmpty;
              return GestureDetector(
                onTap: () => ref
                    .read(currentFolderIdProvider.notifier)
                    .setFolder(folder.id),
                child: Text(
                  folder.name,
                  style: TextStyle(
                    color: isHovered
                        ? palette.primary
                        : (folder.id == currentId
                            ? palette.text
                            : palette.text.withValues(alpha: 0.5)),
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              );
            },
          ),
        );
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: path),
    );
  }
}
