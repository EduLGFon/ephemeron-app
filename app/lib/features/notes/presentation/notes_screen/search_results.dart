part of '../notes_screen.dart';

// Search results screen.

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.query,
    required this.hits,
    required this.onOpen,
  });

  final String query;
  final List<dynamic> hits;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Results for "$query"')),
      body: hits.isEmpty
          ? const Center(child: Text('No matches'))
          : RepaintBoundary(
              child: ListView(
                children: [
                  for (final h in hits)
                    ListTile(
                      title: Text((h.note as Note).title),
                      subtitle: Text(
                        (h.snippet as String)
                            .replaceAll('<b>', '')
                            .replaceAll('</b>', ''),
                      ),
                      onTap: () => onOpen((h.note as Note).id),
                    ),
                ],
              ),
            ),
    );
  }
}
