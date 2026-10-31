import 'package:ephemeron/data/services/home_widget_callback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseToggleUri handles task toggle', () {
    final req = parseToggleUri(Uri.parse('ephemeron://toggle/task/abc'));
    expect(req, isNotNull);
    expect(req!.kind, 'task');
    expect(req.id, 'abc');
  });

  test('parseToggleUri handles habit toggle', () {
    final req = parseToggleUri(Uri.parse('ephemeron://toggle/habit/h1'));
    expect(req, isNotNull);
    expect(req!.kind, 'habit');
  });

  test('parseToggleUri rejects non-toggle URIs', () {
    expect(parseToggleUri(null), isNull);
    expect(parseToggleUri(Uri.parse('ephemeron://open')), isNull);
    expect(parseToggleUri(Uri.parse('ephemeron://toggle/note/x')), isNull);
  });
}
