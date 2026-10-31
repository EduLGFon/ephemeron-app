// Developer log with a hard 500-line cap. Never log tokens, user ids,
// calendar content, task content, notes, or other personal data.
// See ARCHITECTURE.md section 6.4.
class LogEntry {
  LogEntry(this.level, this.message, this.time);
  final String level;
  final String message;
  final DateTime time;

  @override
  String toString() => '${time.toUtc().toIso8601String()} [$level] $message';
}

class AppLogger {
  AppLogger({this.maxLines = 500});
  final int maxLines;
  final List<LogEntry> _entries = <LogEntry>[];

  List<LogEntry> get entries => List<LogEntry>.unmodifiable(_entries);

  void debug(String message) => _add('DEBUG', message);
  void info(String message) => _add('INFO', message);
  void warn(String message) => _add('WARN', message);
  void error(String message, [Object? error]) =>
      _add('ERROR', error == null ? message : '$message: $error');

  void _add(String level, String message) {
    _entries.add(LogEntry(level, message, DateTime.now().toUtc()));
    while (_entries.length > maxLines) {
      _entries.removeAt(0);
    }
  }

  void clear() => _entries.clear();
}
