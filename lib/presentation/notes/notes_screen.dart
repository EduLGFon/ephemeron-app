import 'package:drift/drift.dart' show Value;
import '../../features/quick_add/application/quick_add_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_engine_provider.dart';
import '../../core/theme/theme_palettes.dart';
import '../../data/local/database.dart';
import '../../features/notes/application/notes_providers.dart';
import '../../features/notes/data/notes_repository.dart';
import 'package:ephemeron/core/widgets/app_loading_indicator.dart';
import '../widgets/keyboard_avoid_padding.dart';
import 'note_form_sheet.dart';
import 'widgets/note_card.dart';
import 'widgets/note_folder_breadcrumbs.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  String? _dragHoverId;
  bool _isSearching = false;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(themeEngineProvider);
    final currentFolderId = ref.watch(currentFolderIdProvider);
    final notesAsync = ref.watch(notesStreamProvider);
    final foldersAsync = ref.watch(foldersStreamProvider);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _isSearching
            ? IconButton(
                icon: Icon(Icons.arrow_back, color: palette.text),
                onPressed: () => setState(() {
                  _isSearching = false;
                  _searchQuery = '';
                }),
              )
            : null,
        title: _isSearching
            ? TextField(
                autofocus: true,
                style: TextStyle(color: palette.text, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Search title, content, #tag...',
                  hintStyle:
                      TextStyle(color: palette.text.withValues(alpha: 0.4)),
                  border: InputBorder.none,
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              )
            : foldersAsync.when(
                data: (allFolders) => NoteFolderBreadcrumbs(
                  currentId: currentFolderId,
                  allFolders: allFolders,
                  palette: palette,
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
        actions: _isSearching
            ? [
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.clear, color: palette.text),
                    onPressed: () => setState(() => _searchQuery = ''),
                  ),
              ]
            : [
                IconButton(
                  icon: Icon(Icons.create_new_folder_outlined,
                      color: palette.text),
                  tooltip: 'New Folder',
                  onPressed: () => _showCreateFolderDialog(context, ref),
                ),
                IconButton(
                  icon: Icon(Icons.search, color: palette.text),
                  tooltip: 'Search',
                  onPressed: () => setState(() => _isSearching = true),
                ),
              ],
      ),
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(
            child: SizedBox(height: 16),
          ),
          SliverToBoxAdapter(
            child: foldersAsync.when(
              data: (allFolders) {
                final visibleFolders = allFolders
                    .where((f) => f.parentFolderId == currentFolderId)
                    .toList();
                final allNotes = notesAsync.value ?? const [];
                return _buildFoldersList(
                    visibleFolders, allNotes, palette, ref);
              },
              loading: () => const SizedBox(
                  height: 110, child: Center(child: AppLoadingIndicator())),
              error: (err, _) => Center(
                  child: Text('Error loading folders: $err',
                      style: TextStyle(color: palette.text))),
            ),
          ),
          const SliverToBoxAdapter(
            child: SizedBox(height: 12),
          ),
          notesAsync.when(
            data: (allNotes) {
              final q = _searchQuery.trim().toLowerCase();
              final visibleNotes = allNotes.where((n) {
                if (q.isEmpty) {
                  return n.folderId == currentFolderId;
                }
                final matchesText = n.title.toLowerCase().contains(q) ||
                    n.content.toLowerCase().contains(q);
                bool matchesFolder = false;
                if (foldersAsync.value != null) {
                  final matchingFolders = foldersAsync.value!
                      .where((f) => f.name.toLowerCase().contains(q))
                      .map((f) => f.id)
                      .toSet();
                  if (n.folderId != null &&
                      matchingFolders.contains(n.folderId)) {
                    matchesFolder = true;
                  }
                }
                final isInsideFolder =
                    currentFolderId == null || n.folderId == currentFolderId;
                return (matchesText || matchesFolder) && isInsideFolder;
              }).toList();

              if (visibleNotes.isEmpty) {
                return SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(48.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notes,
                              size: 48,
                              color: palette.text.withValues(alpha: 0.1)),
                          const SizedBox(height: 8),
                          Text('No notes yet',
                              style: TextStyle(
                                  color: palette.text.withValues(alpha: 0.4),
                                  fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final grouped = _groupNotesByDate(visibleNotes);
              final keys = grouped.keys.toList();

              return SliverList.builder(
                itemCount: keys.length,
                itemBuilder: (context, idx) {
                  final key = keys[idx];
                  final groupNotes = grouped[key]!;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding:
                            const EdgeInsets.only(left: 16, top: 20, bottom: 8),
                        child: Text(
                          key,
                          style: TextStyle(
                              color: palette.text.withValues(alpha: 0.5),
                              fontSize: 14,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.9,
                        ),
                        itemCount: groupNotes.length,
                        itemBuilder: (context, noteIdx) {
                          final note = groupNotes[noteIdx];
                          return RepaintBoundary(
                            child: DraggableNoteCard(
                              note: note,
                              palette: palette,
                              onTap: () => ref
                                  .read(quickAddProvider.notifier)
                                  .expand(note),
                              onLongPress: () =>
                                  _showDeleteNoteDialog(context, ref, note),
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              );
            },
            loading: () => const SliverToBoxAdapter(
                child: Center(
                    child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator()))),
            error: (err, _) => SliverToBoxAdapter(
                child: Center(
                    child: Text('Error loading notes: $err',
                        style: TextStyle(color: palette.text)))),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: palette.primary,
        foregroundColor: palette.background,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: () {
          final sheet = Center(
            child: SingleChildScrollView(
              child: Material(
                color: Colors.transparent,
                child: const RepaintBoundary(child: NoteFormSheet()),
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
        },
        child: const Icon(Icons.edit_outlined, size: 24),
      ),
    );
  }

  Widget _buildFoldersList(
    List<NoteFolder> folders,
    List<Note> notes,
    AppPalette palette,
    WidgetRef ref,
  ) {
    if (folders.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: folders.length,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (context, index) {
          final folder = folders[index];
          final noteCount = notes.where((n) => n.folderId == folder.id).length;
          final isHovered = _dragHoverId == folder.id;

          return DragTarget<Note>(
            onWillAcceptWithDetails: (details) {
              setState(() => _dragHoverId = folder.id);
              return details.data.folderId != folder.id;
            },
            onLeave: (_) => setState(() => _dragHoverId = null),
            onAcceptWithDetails: (details) async {
              setState(() => _dragHoverId = null);
              await ref
                  .read(notesRepositoryProvider)
                  .moveNoteToFolder(details.data.id, folder.id);
            },
            builder: (context, candidateData, rejectedData) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 100,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: isHovered
                      ? palette.primary.withValues(alpha: 0.15)
                      : palette.text.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isHovered
                        ? palette.primary
                        : palette.text.withValues(alpha: 0.08),
                    width: isHovered ? 2 : 1,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => ref
                      .read(currentFolderIdProvider.notifier)
                      .setFolder(folder.id),
                  onLongPress: () =>
                      _showDeleteFolderDialog(context, ref, folder),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: (isHovered
                                        ? palette.primary
                                        : palette.primary)
                                    .withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isHovered ? Icons.folder_open : Icons.folder,
                                color: palette.primary,
                                size: 20,
                              ),
                            ),
                            Text(
                              '$noteCount',
                              style: TextStyle(
                                color: palette.text.withValues(alpha: 0.5),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          folder.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isHovered ? palette.primary : palette.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Map<String, List<Note>> _groupNotesByDate(List<Note> notes) {
    final grouped = <String, List<Note>>{};
    final now = DateTime.now();
    for (final note in notes) {
      final dt = note.createdAt;
      String key;
      if (dt.year == now.year && dt.month == now.month) {
        key = 'This month';
      } else if (dt.year == now.year) {
        key = _getMonthName(dt.month);
      } else {
        key = '${dt.year}';
      }
      grouped.putIfAbsent(key, () => []).add(note);
    }
    return grouped;
  }

  String _getMonthName(int month) => switch (month) {
        1 => 'Jan',
        2 => 'Feb',
        3 => 'Mar',
        4 => 'Apr',
        5 => 'May',
        6 => 'Jun',
        7 => 'Jul',
        8 => 'Aug',
        9 => 'Sep',
        10 => 'Oct',
        11 => 'Nov',
        _ => 'Dec',
      };

  void _showCreateFolderDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    final palette = ref.read(themeEngineProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text('New Folder', style: TextStyle(color: palette.text)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: palette.text),
          decoration: InputDecoration(
            hintText: 'Folder name',
            hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.5)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: palette.primary)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel',
                style: TextStyle(color: palette.text.withValues(alpha: 0.6))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: palette.primary),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final parentId = ref.read(currentFolderIdProvider);
                await ref.read(notesRepositoryProvider).createFolder(
                      NoteFoldersCompanion.insert(
                          name: name, parentFolderId: Value(parentId)),
                    );
                if (context.mounted) Navigator.of(context).pop();
              }
            },
            child: Text('Create', style: TextStyle(color: palette.background)),
          ),
        ],
      ),
    );
  }

  void _showDeleteFolderDialog(
      BuildContext context, WidgetRef ref, NoteFolder folder) {
    final palette = ref.read(themeEngineProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text('Delete folder?', style: TextStyle(color: palette.text)),
        content: Text(
          'This will permanently delete "${folder.name}". Notes inside will be moved to the parent directory.',
          style: TextStyle(color: palette.text.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel',
                style: TextStyle(color: palette.text.withValues(alpha: 0.6))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await ref.read(notesRepositoryProvider).deleteFolder(folder.id);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Delete',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDeleteNoteDialog(BuildContext context, WidgetRef ref, Note note) {
    final palette = ref.read(themeEngineProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text('Delete note?', style: TextStyle(color: palette.text)),
        content: Text(
          'Are you sure you want to permanently delete this note?',
          style: TextStyle(color: palette.text.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel',
                style: TextStyle(color: palette.text.withValues(alpha: 0.6))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await ref.read(notesRepositoryProvider).deleteNote(note.id);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Delete',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
