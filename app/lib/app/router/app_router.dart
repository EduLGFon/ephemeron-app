import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shell/app_shell.dart';
import '../../features/calendar/presentation/calendar_screen.dart';
import '../../features/countdowns/presentation/countdowns_screen.dart';
import '../../features/focus/presentation/focus_screen.dart';
import '../../features/habits/presentation/habits_screen.dart';
import '../../features/tasks/presentation/matrix_screen.dart';
import '../../features/tasks/presentation/tasks_screen.dart';
import '../../features/alarms/presentation/alarm_settings_screen.dart';
import '../../features/alarms/presentation/ring_screen.dart';
import '../../features/notes/presentation/notes_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tab0',
                builder: (context, state) => const CalendarScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tab1',
                builder: (context, state) => const TasksScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tab2',
                builder: (context, state) => const MatrixScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tab3',
                builder: (context, state) => const HabitsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tab4',
                builder: (context, state) => const CountdownsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tab5',
                builder: (context, state) => const FocusScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tab6',
                builder: (context, state) => const NotesScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: '/ring', builder: (context, state) => const RingScreen()),
      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(
        path: '/alarm-settings',
        builder: (context, state) => const AlarmSettingsScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
    redirect: (context, state) {
      if (state.uri.path == '/') return '/tab0';
      return null;
    },
  );
});
