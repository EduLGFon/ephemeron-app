// Global search screen: one field across tasks, events, notes,
// habits, countdowns and tags, with type filters.
// Result rows are display-only; deep navigation ships separately.
import 'package:flutter/material.dart';
import 'package:ephemeron/core/time/device_date_format.dart';
import 'package:ephemeron/l10n/src/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/note_repository.dart';
import 'package:ephemeron/domain/sources/source_label.dart';
import 'package:ephemeron/features/calendar/application/calendar_providers.dart';
import 'package:ephemeron/features/settings/application/settings_providers.dart';
import 'package:ephemeron/features/tasks/application/tasks_providers.dart';
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
  bool _restored = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_restored) {
      _restored = true;
      Future.microtask(() async {
        try {
          final repo = await ref.read(settingsRepositoryProvider.future);
          final q = repo.searchQuery;
          final scopeName = repo.searchScope;
          if (!mounted) return;
          if (q.isNotEmpty) {
            _controller.text = q;
            ref.read(searchQueryProvider.notifier).set(q);
          }
          final scope = SearchScope.values.firstWhere(
            (s) => s.name == scopeName,
            orElse: () => SearchScope.all,
          );
          ref.read(searchScopeProvider.notifier).set(scope);
          // Track the route so restarts return here.
          await repo.setLastRoute('/search');
        } catch (_) {}
      });
    }
  }

  Future<void> _onQueryChanged(String v) async {
    ref.read(searchQueryProvider.notifier).set(v);
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      await repo.setSearchQuery(v);
    } catch (_) {}
  }

  Future<void> _onScopeChanged(SearchScope s) async {
    ref.read(searchScopeProvider.notifier).set(s);
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      await repo.setSearchScope(s.name);
    } catch (_) {}
  }

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
              onChanged: _onQueryChanged,
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
                    onSelected: (_) => _onScopeChanged(s),
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
    final listsById = ref.watch(taskListsByIdProvider);
    final calendars = ref.watch(calendarsProvider).value ?? const <Calendar>[];
    final calendarsById = {for (final c in calendars) c.id: c};
    final items = <Widget>[];
    if (_show(scope, SearchScope.tasks)) {
      items.add(
        _Group<Task>(
          title: l.searchTasks,
          async: ref.watch(searchTasksProvider),
          tile: (t) {
            final list = t.listId == null ? null : listsById[t.listId];
            final source = sourceLabel(
              name: list?.name,
              account: accountForSource(
                googleAccount: t.googleAccount,
                microsoftAccount: t.microsoftAccount,
              ),
              fallbackAccount: accountForSource(
                googleAccount: list?.googleAccount,
                microsoftAccount: list?.microsoftAccount,
              ),
            );
            return ListTile(
              leading: const Icon(Icons.checklist_outlined),
              title: Text(t.title),
              subtitle: (source == null && t.dueDate == null)
                  ? null
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (source != null) Text(source),
                        if (t.dueDate != null)
                          Text(DeviceDateFormat.dateIso(context, t.dueDate!)),
                      ],
                    ),
            );
          },
        ),
      );
    }
    if (_show(scope, SearchScope.events)) {
      items.add(
        _Group<Event>(
          title: l.searchEvents,
          async: ref.watch(searchEventsProvider),
          tile: (e) {
            final calendar = calendarsById[e.calendarId];
            final source = sourceLabel(
              name: calendar?.name,
              account: accountForSource(
                googleAccount: e.googleAccount,
                microsoftAccount: e.microsoftAccount,
              ),
              fallbackAccount: accountForSource(
                googleAccount: calendar?.googleAccount,
                microsoftAccount: calendar?.microsoftAccount,
              ),
              isLocal:
                  calendar == null ||
                  (calendar.source != 'google' &&
                      calendar.source != 'microsoft'),
            );
            return ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: Text(e.title.isEmpty ? '(no title)' : e.title),
              subtitle: (source == null && e.location == null)
                  ? null
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (source != null) Text(source),
                        if (e.location != null) Text(e.location!),
                      ],
                    ),
            );
          },
        ),
      );
    }
    if (_show(scope, SearchScope.notes)) {
      items.add(
        _Group<NoteSearchHit>(
          title: l.searchNotes,
          async: ref.watch(searchNotesProvider),
          tile: (h) => ListTile(
            leading: const Icon(Icons.note_outlined),
            title: Text(h.note.title.isEmpty ? '(no title)' : h.note.title),
            subtitle: Text(h.snippet, maxLines: 2),
          ),
        ),
      );
    }
    if (_show(scope, SearchScope.habits)) {
      items.add(
        _Group<Habit>(
          title: l.searchHabits,
          async: ref.watch(searchHabitsProvider),
          tile: (h) => ListTile(
            leading: const Icon(Icons.repeat_outlined),
            title: Text(h.name),
          ),
        ),
      );
    }
    if (_show(scope, SearchScope.countdowns)) {
      items.add(
        _Group<Countdown>(
          title: l.searchCountdowns,
          async: ref.watch(searchCountdownsProvider),
          tile: (c) => ListTile(
            leading: const Icon(Icons.hourglass_bottom_outlined),
            title: Text(c.title),
            subtitle: c.targetDate == null
                ? null
                : Text(DeviceDateFormat.dateIso(context, c.targetDate!)),
          ),
        ),
      );
    }
    if (_show(scope, SearchScope.tags)) {
      items.add(
        _Group<Tag>(
          title: l.searchTags,
          async: ref.watch(searchTagsProvider),
          tile: (t) =>
              ListTile(leading: const Icon(Icons.tag), title: Text(t.name)),
        ),
      );
    }
    return RepaintBoundary(
      child: ListView.builder(
        itemCount: items.length,
        itemBuilder: (_, i) => items[i],
      ),
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
