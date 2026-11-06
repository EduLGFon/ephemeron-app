// Drift table definitions for the app database. Split into part files under
// `tables/` by domain; this library re-exports them via `part` directives.
// Common syncable columns are repeated per table (Drift has no mixins for
// columns that participate in the table definition cleanly). All timestamps
// are UTC ms.

import 'package:drift/drift.dart';

part 'tables/calendar.dart';
part 'tables/tasks.dart';
part 'tables/habits.dart';
part 'tables/notes.dart';
part 'tables/misc.dart';
