/// A curated, selectable set of goal units — replaces what used to be a
/// free-text field. `goalUnit` in the database is still plain text (no
/// schema change needed for this), but the UI now offers this list via a
/// dropdown instead of a text box, and [isTimeBased] lets
/// FocusRepository credit session time to a habit's goal exactly, rather
/// than guessing from a substring match against whatever the user typed.
enum HabitGoalUnit {
  minutes('min', isTimeBased: true),
  hours('hour', isTimeBased: true),
  milliliters('ml'),
  liters('L'),
  glasses('glass'),
  kilometers('km'),
  miles('mi'),
  steps('steps'),
  pages('pages'),
  times('times'),
  reps('reps'),
  calories('kcal');

  const HabitGoalUnit(this.label, {this.isTimeBased = false});

  final String label;
  final bool isTimeBased;

  /// Null means either no unit stored, or the stored text doesn't match
  /// any known option — which happens for habits created via the
  /// "Custom..." free-text fallback, still supported for anything this
  /// curated list doesn't cover.
  static HabitGoalUnit? tryParse(String? raw) {
    if (raw == null) return null;
    for (final unit in values) {
      if (unit.label == raw) return unit;
    }
    return null;
  }
}
