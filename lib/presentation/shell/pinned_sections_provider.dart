import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'nav_section.dart';

/// Returns the sections currently pinned to the bottom bar, in order.
/// Hardcoded to the defaults for this build step — swap this for a
/// SharedPreferences-backed Notifier when the reorder/customize settings
/// screen is built, without touching AppShell or the router at all.
final pinnedSectionsProvider = Provider<List<NavSection>>((ref) {
  return defaultPinnedSections;
});

final overflowSectionsProvider = Provider<List<NavSection>>((ref) {
  return defaultOverflowSections;
});
