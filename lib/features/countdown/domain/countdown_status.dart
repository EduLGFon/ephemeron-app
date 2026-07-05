/// Computed, not stored — derived fresh from a Countdown's targetDate/
/// isYearly/showAge whenever displayed.
class CountdownStatus {
  const CountdownStatus({
    required this.isFuture,
    required this.days,
    required this.effectiveDate,
    this.age,
  });

  /// true = "x days left" (effectiveDate is upcoming), false = "x days
  /// since" (effectiveDate — the original targetDate for non-yearly
  /// countdowns — is in the past, with no future occurrence to count to).
  final bool isFuture;
  final int days;
  final DateTime effectiveDate;
  final int? age;

  static CountdownStatus compute({
    required DateTime targetDate,
    required bool isYearly,
    required bool showAge,
  }) {
    final today = _normalize(DateTime.now());
    final target = _normalize(targetDate);

    if (!isYearly) {
      final diff = target.difference(today).inDays;
      return CountdownStatus(isFuture: diff >= 0, days: diff.abs(), effectiveDate: target);
    }

    // Yearly: find this year's occurrence, or next year's if it already
    // passed — a countdown to a recurring date is never "in the past".
    var occurrence = DateTime(today.year, target.month, target.day);
    if (occurrence.isBefore(today)) {
      occurrence = DateTime(today.year + 1, target.month, target.day);
    }
    final days = occurrence.difference(today).inDays;
    final age = showAge ? occurrence.year - target.year : null;
    return CountdownStatus(isFuture: true, days: days, effectiveDate: occurrence, age: age);
  }

  static DateTime _normalize(DateTime d) => DateTime(d.year, d.month, d.day);
}
