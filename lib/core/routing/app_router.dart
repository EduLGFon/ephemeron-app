import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/google/google_auth_provider.dart';
import '../../features/auth/presentation/auth_screen.dart';
import '../../presentation/shell/app_shell.dart';
import '../../features/calendar/presentation/calendar_screen.dart';
import '../../features/tasks/presentation/tasks_screen.dart';
import '../../features/matrix/presentation/matrix_screen.dart';
import '../../features/habits/presentation/habits_screen.dart';
import '../../features/countdown/presentation/countdown_screen.dart';
import '../../features/focus/presentation/focus_screen.dart';
import '../../presentation/notes/notes_screen.dart';
import 'root_navigator_key.dart';

/// Branch order here is load-bearing: it must match NavSection's
/// branchIndex values exactly (calendar=0 ... notes=6). All 7 branches
/// are always defined, regardless of which ones are currently pinned to
/// the visible bottom bar — that's a presentation-layer decision made in
/// AppShell, not a routing one. Keeping routing static like this avoids
/// the real complexity of reconfiguring go_router itself at runtime.
/// Navigator key lives in root_navigator_key.dart — shared with
/// alarm_scheduler.dart, see that file's usage for why.

/// ChangeNotifier bridging Riverpod's googleAccountProvider stream to
/// GoRouter's refreshListenable. Whenever auth state changes the router
/// re-runs its redirect logic automatically.
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(Ref ref) {
    ref.listen(googleAccountProvider, (_, __) => notifyListeners());
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final authNotifier = _AuthNotifier(ref);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/auth',
    debugLogDiagnostics: false,
    refreshListenable: authNotifier,
    redirect: (context, state) async {
      final isOnAuth = state.matchedLocation == '/auth';

      // While auth is still initializing, don't redirect yet — stay where we are.
      final accountAsync = ref.read(googleAccountProvider);
      if (accountAsync.isLoading) return null;

      final isSignedIn = accountAsync.whenData((a) => a).value != null;

      if (isSignedIn && isOnAuth) {
        // Already authenticated — skip the auth screen and restore last screen.
        final prefs = await SharedPreferences.getInstance();
        final lastScreen = prefs.getString('settings.lastScreen') ?? '/calendar';
        return lastScreen;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/auth',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const AuthScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/calendar',
                builder: (context, state) => const CalendarScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tasks',
                builder: (context, state) => const TasksScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/matrix',
                builder: (context, state) => const MatrixScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/habits',
                builder: (context, state) => const HabitsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/countdown',
                builder: (context, state) => const CountdownScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/focus',
                builder: (context, state) => const FocusScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/notes',
                builder: (context, state) => const NotesScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
