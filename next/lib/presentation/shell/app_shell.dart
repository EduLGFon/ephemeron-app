import 'package:flutter/material.dart';

import '../../features/calendar/presentation/calendar_screen.dart';
import '../../features/tasks/presentation/tasks_screen.dart';
import '../../features/matrix/presentation/matrix_screen.dart';
import '../../features/habits/presentation/habits_screen.dart';
import '../../features/countdown/presentation/countdown_screen.dart';
import '../../features/focus/presentation/focus_screen.dart';
import '../../presentation/notes/notes_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  final _screens = const [
    CalendarScreen(),
    TasksScreen(),
    MatrixScreen(),
    HabitsScreen(),
    CountdownScreen(),
    FocusScreen(),
    NotesScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_today), label: 'Calendar'),
          NavigationDestination(icon: Icon(Icons.task_alt), label: 'Tasks'),
          NavigationDestination(icon: Icon(Icons.grid_view), label: 'Matrix'),
          NavigationDestination(icon: Icon(Icons.repeat), label: 'Habits'),
          NavigationDestination(icon: Icon(Icons.timer), label: 'Countdown'),
          NavigationDestination(icon: Icon(Icons.center_focus_strong), label: 'Focus'),
          NavigationDestination(icon: Icon(Icons.note), label: 'Notes'),
        ],
      ),
    );
  }
}