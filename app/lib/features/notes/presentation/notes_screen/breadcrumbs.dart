part of '../notes_screen.dart';

// Breadcrumbs widget.

class _Breadcrumbs extends ConsumerWidget {
  const _Breadcrumbs({required this.folderId, required this.onNavigate});

  final String? folderId;
  final ValueChanged<String?> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (folderId == null) {
      return const ListTile(title: Text('All folders'), enabled: false);
    }
    return FutureBuilder(
      future: ref.read(noteRepositoryProvider).breadcrumbs(folderId!),
      builder: (ctx, snap) {
        final crumbs = snap.data ?? const <Folder>[];
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              TextButton(
                onPressed: () => onNavigate(null),
                child: const Text('All'),
              ),
              for (final f in crumbs) ...[
                const Text('/'),
                TextButton(
                  onPressed: () => onNavigate(f.id),
                  child: Text(f.name),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
