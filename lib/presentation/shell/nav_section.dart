import 'package:flutter/material.dart';

/// One entry in the bottom navigation. `branchIndex` maps 1:1 to the
/// StatefulShellRoute branch order defined in app_router.dart — the two
/// files must stay in sync (kept in one enum specifically to make that
/// sync unmissable at compile time).
enum NavSection {
  calendar(0, 'Calendar', Icons.calendar_month_outlined, Icons.calendar_month),
  tasks(1, 'Tasks', Icons.checklist_outlined, Icons.checklist),
  matrix(2, 'Matrix', Icons.grid_view_outlined, Icons.grid_view),
  habits(3, 'Habits', Icons.repeat_outlined, Icons.repeat),
  countdown(4, 'Countdown', Icons.hourglass_bottom_outlined, Icons.hourglass_bottom),
  focus(5, 'Focus', Icons.timer_outlined, Icons.timer),
  notes(6, 'Notes', Icons.notes_outlined, Icons.notes);

  const NavSection(this.branchIndex, this.label, this.icon, this.selectedIcon);

  final int branchIndex;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Default set of sections pinned to the bottom bar. Seven destinations in
/// one bar is past what Material's own guidance recommends (3-5) and
/// would crowd on smaller phones, so the default here surfaces the five
/// sections expected to be opened most often; Matrix and Countdown sit
/// behind "More" until the reorder/customize UI (a later build step)
/// lets the user promote them instead.
const List<NavSection> defaultPinnedSections = [
  NavSection.calendar,
  NavSection.tasks,
  NavSection.habits,
  NavSection.focus,
  NavSection.notes,
];

const List<NavSection> defaultOverflowSections = [
  NavSection.matrix,
  NavSection.countdown,
];
