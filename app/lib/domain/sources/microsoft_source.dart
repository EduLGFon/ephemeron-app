// Pure helpers to detect Microsoft-originated items. Microsoft/Graph writes are
// not supported, so UI must not offer edits or completions for these items.
library;

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

bool isMicrosoftTask({
  String? taskMicrosoftAccount,
  String? listMicrosoftAccount,
}) {
  return _nonEmpty(taskMicrosoftAccount) != null ||
      _nonEmpty(listMicrosoftAccount) != null;
}

bool isMicrosoftEvent({
  String? eventMicrosoftAccount,
  String? calendarSource,
  String? calendarMicrosoftAccount,
}) {
  if (_nonEmpty(eventMicrosoftAccount) != null) return true;
  if (calendarSource == 'microsoft') return true;
  if (_nonEmpty(calendarMicrosoftAccount) != null) return true;
  return false;
}
