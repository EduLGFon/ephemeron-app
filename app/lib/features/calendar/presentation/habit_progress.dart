// Compact goal/progress labels shared by habit markers, blocks, and sheets.

String formatHabitAmount(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  var text = value.toStringAsFixed(2);
  while (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return text;
}

String habitUnitSuffix(String? unit) {
  final trimmed = unit?.trim();
  if (trimmed == null || trimmed.isEmpty) return '';
  return ' $trimmed';
}

String habitProgressText(double amount, double goal, {String? unit}) {
  return '${formatHabitAmount(amount)} / ${formatHabitAmount(goal)}'
      '${habitUnitSuffix(unit)}';
}

String habitStepLabel(double step, String? unit) {
  return 'Add ${formatHabitAmount(step)}${habitUnitSuffix(unit)}';
}
