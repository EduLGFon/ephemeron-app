import 'package:flutter/material.dart';

enum AppSection {
  calendar('Calendar', Icons.calendar_month_outlined),
  tasks('Tasks', Icons.checklist_outlined),
  matrix('Matrix', Icons.grid_view_outlined),
  habits('Habits', Icons.repeat_outlined),
  countdowns('Countdowns', Icons.hourglass_bottom_outlined),
  focus('Focus', Icons.timer_outlined),
  notes('Notes', Icons.note_outlined);

  const AppSection(this.title, this.icon);
  final String title;
  final IconData icon;
}

const List<String> sectionTitles = <String>[
  'Calendar',
  'Tasks',
  'Matrix',
  'Habits',
  'Countdowns',
  'Focus',
  'Notes',
];
