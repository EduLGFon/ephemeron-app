part of '../notes_screen.dart';

// Trash screen.

class _TrashScreen extends ConsumerWidget {
  const _TrashScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trashAsync = ref.watch(noteTrashProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Trash')),
      body: trashAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Could not load.')),
        data: (notes) {
          if (notes.isEmpty) {
            return const Center(child: Text('Trash is empty'));
          }
          return ListView.builder(
            itemCount: notes.length,
            itemBuilder: (context, i) {
              final n = notes[i];
              return ListTile(
                title: Text(n.title),
                trailing: IconButton(
                  icon: const Icon(Icons.restore),
                  onPressed: () =>
                      ref.read(noteRepositoryProvider).restoreNote(n.id),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
