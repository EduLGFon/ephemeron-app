import 'package:ephemeron/domain/sources/source_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('combines calendar name and account e-mail', () {
    expect(
      sourceLabel(name: 'Work', account: 'me@example.com'),
      'Work - me@example.com',
    );
  });

  test('falls back to name when account is missing', () {
    expect(sourceLabel(name: 'Work'), 'Work');
  });

  test('falls back to account when name is missing', () {
    expect(sourceLabel(account: 'me@example.com'), 'me@example.com');
  });

  test('shows the local label for device sources', () {
    expect(
      sourceLabel(name: 'Birthdays', isLocal: true),
      'Birthdays - On this device',
    );
    expect(sourceLabel(isLocal: true), localSourceLabel);
  });

  test('item account overrides the fallback account', () {
    expect(
      sourceLabel(
        name: 'Work',
        account: 'item@example.com',
        fallbackAccount: 'list@example.com',
      ),
      'Work - item@example.com',
    );
  });

  test('blank values fall through to the next source', () {
    expect(
      sourceLabel(
        name: '  Work  ',
        account: '   ',
        fallbackAccount: ' list@example.com ',
      ),
      'Work - list@example.com',
    );
  });

  test('returns null when there is nothing to show', () {
    expect(sourceLabel(), isNull);
    expect(sourceLabel(name: ' ', account: ''), isNull);
  });
}
