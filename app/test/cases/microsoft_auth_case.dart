import 'dart:convert';

import 'package:ephemeron/core/config/safe_storage.dart';
import 'package:ephemeron/features/auth/data/microsoft_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeStorage extends SafeSecureStorage {
  final Map<String, String> data = {};

  List<String> _split(String key) {
    final v = data[key];
    if (v == null || v.isEmpty) return const [];
    return v.split(',').where((e) => e.isNotEmpty).toList();
  }

  @override
  Future<List<String>> microsoftAccounts() async =>
      _split('microsoft.accounts');

  @override
  Future<void> saveMicrosoftAccounts(List<String> accounts) async {
    data['microsoft.accounts'] = accounts.join(',');
  }

  @override
  Future<String?> microsoftActiveAccount() async =>
      data['microsoft.activeAccount'];

  @override
  Future<void> saveMicrosoftActiveAccount(String? email) async {
    if (email == null || email.isEmpty) {
      data.remove('microsoft.activeAccount');
    } else {
      data['microsoft.activeAccount'] = email;
    }
  }

  @override
  Future<void> saveMicrosoftTokensFor({
    required String account,
    required String accessToken,
    String? refreshToken,
    required int expiryMs,
  }) async {
    data['microsoft.$account.accessToken'] = accessToken;
    if (refreshToken != null) {
      data['microsoft.$account.refreshToken'] = refreshToken;
    }
    data['microsoft.$account.expiryMs'] = expiryMs.toString();
  }

  @override
  Future<String?> microsoftAccessTokenFor(String account) async =>
      data['microsoft.$account.accessToken'];

  @override
  Future<String?> microsoftRefreshTokenFor(String account) async =>
      data['microsoft.$account.refreshToken'];

  @override
  Future<int?> microsoftExpiryMsFor(String account) async {
    final v = data['microsoft.$account.expiryMs'];
    if (v == null) return null;
    return int.tryParse(v);
  }

  @override
  Future<void> clearMicrosoftFor(String account) async {
    data.remove('microsoft.$account.accessToken');
    data.remove('microsoft.$account.refreshToken');
    data.remove('microsoft.$account.expiryMs');
  }
}

MicrosoftAuth _auth({
  required FakeStorage storage,
  required http.Client client,
}) {
  return MicrosoftAuth(
    storage: storage,
    httpClient: client,
    launcher: (url, scheme) async {
      final uri = Uri.parse(url);
      final state = uri.queryParameters['state']!;
      return '$scheme://oauth/microsoft?code=authcode&state=$state';
    },
  );
}

void main() {
  test('sign-in success persists token and account', () async {
    final storage = FakeStorage();
    final client = MockClient((req) async {
      if (req.url.path.contains('/token')) {
        return http.Response(
          jsonEncode({
            'access_token': 'access1',
            'refresh_token': 'refresh1',
            'expires_in': 3600,
            'token_type': 'Bearer',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'mail': 'user@example.com', 'userPrincipalName': 'upn'}),
        200,
      );
    });
    final auth = _auth(storage: storage, client: client);
    final email = await auth.signIn();
    expect(email, 'user@example.com');
    expect(auth.accounts, ['user@example.com']);
    expect(
      await storage.microsoftAccessTokenFor('user@example.com'),
      'access1',
    );
    expect(
      await storage.microsoftRefreshTokenFor('user@example.com'),
      'refresh1',
    );
    expect(await storage.microsoftActiveAccount(), 'user@example.com');
  });

  test('identity fallback uses userPrincipalName when mail null', () async {
    final storage = FakeStorage();
    final client = MockClient((req) async {
      if (req.url.path.contains('/token')) {
        return http.Response(
          jsonEncode({
            'access_token': 'access2',
            'refresh_token': 'refresh2',
            'expires_in': 3600,
            'token_type': 'Bearer',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'mail': null, 'userPrincipalName': 'upn@example.com'}),
        200,
      );
    });
    final auth = _auth(storage: storage, client: client);
    final email = await auth.signIn();
    expect(email, 'upn@example.com');
  });

  test('state mismatch fails', () async {
    final storage = FakeStorage();
    final client = MockClient((req) async => http.Response('{}', 200));
    final auth = MicrosoftAuth(
      storage: storage,
      httpClient: client,
      launcher: (url, scheme) async =>
          '$scheme://oauth/microsoft?code=authcode&state=wrong',
    );
    expect(() => auth.signIn(), throwsA(isA<MicrosoftAuthException>()));
  });

  test('refresh expired token persists new tokens', () async {
    final storage = FakeStorage();
    await storage.saveMicrosoftAccounts(['user@example.com']);
    await storage.saveMicrosoftActiveAccount('user@example.com');
    await storage.saveMicrosoftTokensFor(
      account: 'user@example.com',
      accessToken: 'oldaccess',
      refreshToken: 'oldrefresh',
      expiryMs: DateTime.now().toUtc().millisecondsSinceEpoch - 1000,
    );
    final client = MockClient((req) async {
      if (req.url.path.contains('/token')) {
        return http.Response(
          jsonEncode({
            'access_token': 'newaccess',
            'refresh_token': 'newrefresh',
            'expires_in': 3600,
            'token_type': 'Bearer',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 200);
    });
    final auth = MicrosoftAuth(storage: storage, httpClient: client);
    await auth.restore();
    final token = await auth.accessToken();
    expect(token, 'newaccess');
    expect(
      await storage.microsoftAccessTokenFor('user@example.com'),
      'newaccess',
    );
    expect(
      await storage.microsoftRefreshTokenFor('user@example.com'),
      'newrefresh',
    );
  });

  test('multiple accounts and sign-out', () async {
    final storage = FakeStorage();
    // Sign in first
    final client = MockClient((req) async {
      if (req.url.path.contains('/token')) {
        return http.Response(
          jsonEncode({
            'access_token': 'a',
            'refresh_token': 'r',
            'expires_in': 3600,
            'token_type': 'Bearer',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'mail': 'first@example.com', 'userPrincipalName': 'first'}),
        200,
      );
    });
    final auth = _auth(storage: storage, client: client);
    await auth.signIn();

    // second sign-in with different email
    final client2 = MockClient((req) async {
      if (req.url.path.contains('/token')) {
        return http.Response(
          jsonEncode({
            'access_token': 'a2',
            'refresh_token': 'r2',
            'expires_in': 3600,
            'token_type': 'Bearer',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'mail': 'second@example.com',
          'userPrincipalName': 'second',
        }),
        200,
      );
    });
    final auth2 = MicrosoftAuth(
      storage: storage,
      httpClient: client2,
      launcher: (url, scheme) async {
        final uri = Uri.parse(url);
        final state = uri.queryParameters['state']!;
        return '$scheme://oauth/microsoft?code=authcode&state=$state';
      },
    );
    // share storage accounts list: reload
    await auth2.restore();
    await auth2.signIn();
    expect(auth2.accounts, contains('first@example.com'));
    expect(auth2.accounts, contains('second@example.com'));

    await auth2.signOut('first@example.com');
    expect(auth2.accounts, isNot(contains('first@example.com')));
    expect(await storage.microsoftAccessTokenFor('first@example.com'), isNull);
  });

  test('fresh sign-in preserves stored accounts', () async {
    final storage = FakeStorage();
    await storage.saveMicrosoftAccounts(['a@example.com', 'b@example.com']);
    await storage.saveMicrosoftActiveAccount('a@example.com');
    final client = MockClient((req) async {
      if (req.url.path.contains('/token')) {
        return http.Response(
          jsonEncode({
            'access_token': 'a3',
            'refresh_token': 'r3',
            'expires_in': 3600,
            'token_type': 'Bearer',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'mail': 'c@example.com', 'userPrincipalName': 'c'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final auth = MicrosoftAuth(
      storage: storage,
      httpClient: client,
      launcher: (url, scheme) async {
        final uri = Uri.parse(url);
        final state = uri.queryParameters['state']!;
        return '$scheme://oauth/microsoft?code=authcode&state=$state';
      },
    );
    final email = await auth.signIn();
    expect(email, 'c@example.com');
    expect(
      await storage.microsoftAccounts(),
      containsAll(['a@example.com', 'b@example.com', 'c@example.com']),
    );
    expect(await storage.microsoftActiveAccount(), 'c@example.com');

    await auth.signOut('b@example.com');
    expect(await storage.microsoftAccounts(), isNot(contains('b@example.com')));
    expect(
      await storage.microsoftAccounts(),
      containsAll(['a@example.com', 'c@example.com']),
    );
  });
}
