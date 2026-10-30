// Client configuration. OAuth client IDs are public identifiers; on
// production builds prefer passing them via --dart-define so the source
// tree stays free of environment-specific values (see README/AGENTS).
class AppConfig {
  static const String androidGoogleClientId = String.fromEnvironment(
    'GOOGLE_ANDROID_CLIENT_ID',
    defaultValue: '927111009905-06l7pnq8jcqbcig3h71542t5s5a4l4bj.apps.googleusercontent.com',
  );
  static const String webGoogleClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '927111009905-v93shl2b2g8oc71t2kamvlpu3ricvet7.apps.googleusercontent.com',
  );
  static const String linuxGoogleClientId = String.fromEnvironment(
    'GOOGLE_LINUX_CLIENT_ID',
    defaultValue: '927111009905-bccs4upvlii9kdatl8b6su4d6mtldqki.apps.googleusercontent.com',
  );
  static const String linuxGoogleClientSecret = String.fromEnvironment(
    'GOOGLE_LINUX_CLIENT_SECRET',
    defaultValue: '',
  );
  static const String webGoogleClientSecret = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_SECRET',
    defaultValue: '',
  );
  static const List<String> googleScopes = [
    'https://www.googleapis.com/auth/calendar',
    'https://www.googleapis.com/auth/tasks',
  ];
  static const String calendarApiBase =
      'https://www.googleapis.com/calendar/v3';
  static const String tasksApiBase = 'https://www.googleapis.com/tasks/v1';
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: '',
  );
  static const int syncIntervalMin = 30;
  static const int syncDebounceSec = 5;
}
