// Client configuration. Secrets never live here; OAuth client IDs are
// public identifiers shipped with the app (see ARCHITECTURE.md).
class AppConfig {
  static const String androidGoogleClientId = String.fromEnvironment(
    'GOOGLE_ANDROID_CLIENT_ID',
    defaultValue: '',
  );
  static const String webGoogleClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );
  static const List<String> googleScopes = [
    'https://www.googleapis.com/auth/calendar',
    'https://www.googleapis.com/auth/tasks',
  ];
  static const String calendarApiBase =
      'https://www.googleapis.com/calendar/v3';
  static const String tasksApiBase = 'https://www.googleapis.com/tasks/v1';
  static const int syncIntervalMin = 30;
  static const int syncDebounceSec = 5;
}
