/// Matches the preset system from the original feature brainstorm.
/// Only [light] and [medium] have real behavior in this MVP step —
/// [strong] and [constant] are defined here so the rest of the app
/// (Tasks, Habits, Events) can reference the full enum now and simply
/// get an [UnimplementedError] if something tries to schedule with them
/// before Phase 2 fills in their behavior, rather than the enum itself
/// needing to change shape later.
enum AlarmPreset {
  /// Standard notification, short sound, no full-screen takeover.
  light,

  /// Full-screen alert with short sound when the screen is off;
  /// degrades to a heads-up pop-up while the phone is actively in use.
  medium,

  /// Phase 2: full-screen alert with long sound.
  strong,

  /// Phase 2: keeps ringing full-screen for ~10 minutes until dismissed.
  constant,
}
