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

part 'search_screen/results.dart';

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
