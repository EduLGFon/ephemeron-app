import 'package:flutter/material.dart';

/// The four built-in sections from the brainstorm. Custom sections are
/// just arbitrary strings in the `Habits.section` column — not
/// represented here, since they don't need any fixed metadata beyond a
/// name the user typed.
class HabitSection {
  const HabitSection(this.id, this.label, this.icon, this.suggestedHour);

  final String id;
  final String label;
  final IconData icon;

  /// Pre-fills the reminder time picker when adding a habit to this
  /// section — a UI convenience only, not a persisted per-section
  /// setting (see the Step 6 README section for why: a real persisted
  /// per-section default would need its own small settings table, out
  /// of scope for this MVP step).
  final int suggestedHour;

  static const morning = HabitSection('morning', 'Morning', Icons.wb_sunny_outlined, 8);
  static const afternoon = HabitSection('afternoon', 'Afternoon', Icons.wb_cloudy_outlined, 14);
  static const night = HabitSection('night', 'Night', Icons.nights_stay_outlined, 20);
  static const other = HabitSection('other', 'Other', Icons.circle_outlined, 12);

  static const defaults = [morning, afternoon, night, other];

  static HabitSection resolve(String id) {
    return defaults.firstWhere((s) => s.id == id, orElse: () => HabitSection(id, id, Icons.label_outline, 12));
  }
}
