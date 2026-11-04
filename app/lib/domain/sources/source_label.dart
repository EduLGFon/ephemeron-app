// Pure display labels for the task list or calendar an item belongs to.
// Labels combine the local name with the signed-in account e-mail and fall
// back to whichever part is available, so callers can omit missing sources.
library;

/// Shown next to device-only calendars that have no account e-mail.
const String localSourceLabel = 'On this device';

/// Builds a display label from a source [name] and account e-mail.
///
/// [account] wins over [fallbackAccount] so an item-level account overrides
/// the account stored on its list or calendar. [isLocal] marks device sources
/// that have no account and therefore get [localSourceLabel] instead of an
/// empty trailing part. Returns null when nothing meaningful is available.
String? sourceLabel({
  String? name,
  String? account,
  String? fallbackAccount,
  bool isLocal = false,
}) {
  final trimmedName = _nonEmpty(name);
  final trimmedAccount = _nonEmpty(account) ?? _nonEmpty(fallbackAccount);
  if (trimmedName != null && trimmedAccount != null) {
    return '$trimmedName - $trimmedAccount';
  }
  if (trimmedName != null) {
    return isLocal ? '$trimmedName - $localSourceLabel' : trimmedName;
  }
  if (trimmedAccount != null) return trimmedAccount;
  return isLocal ? localSourceLabel : null;
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
