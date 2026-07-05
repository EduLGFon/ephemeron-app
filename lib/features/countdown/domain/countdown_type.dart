enum CountdownType {
  holiday(label: 'Holiday', isYearlyByDefault: true, supportsAge: false),
  anniversary(label: 'Anniversary', isYearlyByDefault: true, supportsAge: true),
  birthday(label: 'Birthday', isYearlyByDefault: true, supportsAge: true),
  custom(label: 'Countdown', isYearlyByDefault: false, supportsAge: false);

  const CountdownType({
    required this.label,
    required this.isYearlyByDefault,
    required this.supportsAge,
  });

  final String label;
  final bool isYearlyByDefault;
  final bool supportsAge;
}
