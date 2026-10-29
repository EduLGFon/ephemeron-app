// Global search screen: one field across tasks, events, notes,
// habits, countdowns and tags, with type filters.
// Result rows are display-only; deep navigation ships separately.
import 'package:flutter/material.dart';
import 'package:ephemeron/l10n/src/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/note_repository.dart';
import '../application/search_providers.dart';

Map<SearchScope, String> _scopeLabels(AppLocalizations l) => {
  SearchScope.all: l.searchAll,
  SearchScope.tasks: l.searchTasks,
  SearchScope.events: l.searchEvents,
  SearchScope.notes: l.searchNotes,
  SearchScope.habits: l.searchHabits,
  SearchScope.countdowns: l.searchCountdowns,
  SearchScope.tags: l.searchTags,
};

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(searchScopeProvider);
    final query = ref.watch(searchQueryProvider);
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.searchTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: l.searchHint,
                prefixIcon: const Icon(Icons.search),
              ),
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (v) => ref.read(searchQueryProvider.notifier).set(v),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                for (final s in SearchScope.values) ...[
                  ChoiceChip(
                    label: Text(_scopeLabels(l)[s]!),
                    selected: scope == s,
                    onSelected: (_) =>
                        ref.read(searchScopeProvider.notifier).set(s),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: query.trim().isEmpty
                ? Center(child: Text(l.searchEmpty))
                : _Results(scope: scope, l: l),
          ),
        ],
      ),
    );
  }
}

bool _show(SearchScope scope, SearchScope s) =>
    scope == SearchScope.all || scope == s;

class _Results extends ConsumerWidget {
  const _Results({required this.scope, required this.l});

  final SearchScope scope;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      children: [
        if (_show(scope, SearchScope.tasks))
          _Group<Task>(
            title: l.searchTasks,
            async: ref.watch(searchTasksProvider),
            tile: (t) => ListTile(
              leading: const Icon(Icons.checklist_outlined),
              title: Text(t.title),
              subtitle: t.dueDate == null ? null : Text(t.dueDate!),
            ),
          ),
        if (_show(scope, SearchScope.events))
          _Group<Event>(
            title: l.searchEvents,
            async: ref.watch(searchEventsProvider),
            tile: (e) => ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: Text(e.title.isEmpty ? '(no title)' : e.title),
              subtitle: e.location == null ? null : Text(e.location!),
            ),
          ),
        if (_show(scope, SearchScope.notes))
          _Group<NoteSearchHit>(
            title: l.searchNotes,
            async: ref.watch(searchNotesProvider),
            tile: (h) => ListTile(
              leading: const Icon(Icons.note_outlined),
              title: Text(h.note.title.isEmpty ? '(no title)' : h.note.title),
              subtitle: Text(h.snippet, maxLines: 2),
            ),
          ),
        if (_show(scope, SearchScope.habits))
          _Group<Habit>(
            title: l.searchHabits,
            async: ref.watch(searchHabitsProvider),
            tile: (h) => ListTile(
              leading: const Icon(Icons.repeat_outlined),
              title: Text(h.name),
            ),
          ),
        if (_show(scope, SearchScope.countdowns))
          _Group<Countdown>(
            title: l.searchCountdowns,
            async: ref.watch(searchCountdownsProvider),
            tile: (c) => ListTile(
              leading: const Icon(Icons.hourglass_bottom_outlined),
              title: Text(c.title),
              subtitle: c.targetDate == null ? null : Text(c.targetDate!),
            ),
          ),
        if (_show(scope, SearchScope.tags))
          _Group<Tag>(
            title: l.searchTags,
            async: ref.watch(searchTagsProvider),
            tile: (t) =>
                ListTile(leading: const Icon(Icons.tag), title: Text(t.name)),
          ),
      ],
    );
  }
}

class _Group<T> extends StatelessWidget {
  const _Group({required this.title, required this.async, required this.tile});

  final String title;
  final AsyncValue<List<T>> async;
  final Widget Function(T item) tile;

  @override
  Widget build(BuildContext context) {
    return async.maybeWhen(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                '$title (${items.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final item in items) tile(item),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
