// Typed failures for moving an item to another calendar or task list.
// UI shows [message] directly; it contains no personal data.
class SourceMoveException implements Exception {
  SourceMoveException(this.message);

  final String message;

  @override
  String toString() => 'SourceMoveException: $message';
}
