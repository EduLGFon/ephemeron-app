import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shell/app_shell.dart';
import '../shell/section_placeholder.dart';
import '../../features/calendar/presentation/calendar_screen.dart';
import '../../features/tasks/presentation/matrix_screen.dart';
import '../../features/tasks/presentation/tasks_screen.dart';
import '../../features/alarms/presentation/alarm_settings_screen.dart';
import '../../features/alarms/presentation/ring_screen.dart';
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
          for (var i = 3; i < 7; i++)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/tab$i',
                  builder: (context, state) => SectionPlaceholder(index: i),
                ),
              ],
            ),
        ],
      ),
      GoRoute(path: '/ring', builder: (context, state) => const RingScreen()),
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
