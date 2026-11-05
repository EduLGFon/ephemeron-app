import 'package:ephemeron/domain/sources/source_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accountForSource prefers google account', () {
    expect(
      accountForSource(
        googleAccount: 'g@example.com',
        microsoftAccount: 'm@example.com',
      ),
      'g@example.com',
    );
  });

  test('accountForSource falls back to microsoft account', () {
    expect(
      accountForSource(microsoftAccount: 'm@example.com'),
      'm@example.com',
    );
  });

  test('accountForSource returns null when both missing', () {
    expect(accountForSource(), isNull);
  });

  test('microsoft calendar is not labeled local', () {
    expect(
      sourceLabel(
        name: 'Work',
        account: accountForSource(microsoftAccount: 'm@example.com'),
        isLocal: false,
      ),
      'Work - m@example.com',
    );
  });

  test(
    'local source helper covers google precedence and fallback list account',
    () {
      expect(
        sourceLabel(
          name: 'List',
          account: accountForSource(
            googleAccount: null,
            microsoftAccount: 'm@example.com',
          ),
          fallbackAccount: accountForSource(
            googleAccount: 'g@example.com',
            microsoftAccount: null,
          ),
          isLocal: false,
        ),
        'List - m@example.com',
      );
    },
  );
}
