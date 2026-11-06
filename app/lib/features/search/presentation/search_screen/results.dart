part of '../search_screen.dart';

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
