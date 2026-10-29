import 'package:flutter/widgets.dart';

/// Shared across app_router.dart and alarm_scheduler.dart. The alarm
/// scheduler needs to push the full-screen ring route directly from a
/// notification-tap callback — a context that has no BuildContext of its
/// own — so it pushes through this key's NavigatorState rather than
/// going through go_router's declarative path system, which expects to
/// be driven by URL changes, not ad-hoc pushes from background callbacks.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
