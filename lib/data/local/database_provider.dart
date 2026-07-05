import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'database.dart';

/// Single shared [AppDatabase] instance for the app's lifetime. Repository
/// classes built in later steps (Tasks, Habits, ...) will depend on this
/// rather than opening their own connections.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
