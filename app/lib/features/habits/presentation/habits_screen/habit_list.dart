// Part of the habits screen library: section-grouped habit list.
part of '../habits_screen.dart';

class _HabitList extends StatelessWidget {
  const _HabitList({required this.habits, required this.sections});

  final List<Habit> habits;
  final List<HabitSection> sections;

  @override
  Widget build(BuildContext context) {
    final bySection = <String?, List<Habit>>{};
    for (final h in habits) {
      bySection.putIfAbsent(h.sectionId, () => []).add(h);
    }
    String sectionName(String? id) {
      if (id == null) return 'No section';
      for (final s in sections) {
        if (s.id == id) return s.name;
      }
      return 'No section';
    }

    final orderedKeys = [
      ...sections.map((s) => s.id).where(bySection.containsKey),
      if (bySection.containsKey(null)) null,
      ...bySection.keys.where(
        (k) => k != null && !sections.any((s) => s.id == k),
      ),
    ];
    final items = <Widget>[];
    for (final key in orderedKeys) {
      items.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            sectionName(key),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      );
      items.addAll(bySection[key]!.map((h) => _HabitTile(habit: h)));
    }
    return RepaintBoundary(
      child: ListView.builder(
        itemCount: items.length,
        itemBuilder: (_, i) => items[i],
      ),
    );
  }
}
