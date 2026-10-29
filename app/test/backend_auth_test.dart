// Backend auth suite: session round-trips, silent refresh, logout
// clearing, failed restore, HTTP contract via MockClient.
import 'dart:convert';

import 'package:ephemeron/data/remote/backend_api_client.dart';
import 'package:ephemeron/features/auth/data/backend_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeBackend implements BackendApiClient {
  String? storedRefresh;
  int sessions = 0;
  bool failRefresh = false;

  BackendSession _session(String email) {
    sessions++;
    storedRefresh = 'r$sessions';
    return BackendSession(
      email: email,
      accessToken: 'a$sessions',
      refreshToken: storedRefresh!,
      expiresAtMs: DateTime.now().toUtc().millisecondsSinceEpoch + 900000,
    );
  }

  @override
  Future<BackendSession> register(String email, String password) async =>
      _session(email);

  @override
  Future<BackendSession> login(String email, String password) async =>
      _session(email);

  @override
  Future<BackendSession> refresh(String refreshToken) async {
    if (failRefresh || refreshToken != storedRefresh) {
      throw BackendApiException(401, 'bad refresh');
    }
    return _session('user@example.com');
  }

  @override
  Future<void> logout(String refreshToken) async {
    storedRefresh = null;
  }

  @override
  Future<void> deleteAccount(String accessToken) async {}
}

class MemoryTokenStore implements BackendTokenStore {
  String? token;

  @override
  Future<void> saveRefresh(String token) async => this.token = token;

  @override
  Future<String?> readRefresh() async => token;

  @override
  Future<void> clear() async => token = null;
}

BackendAuth _auth({FakeBackend? fake, MemoryTokenStore? store}) {
  return BackendAuth(
    client: fake ?? FakeBackend(),
    tokenStore: store ?? MemoryTokenStore(),
  );
}

void main() {
  test('login round-trip persists refresh token', () async {
    final store = MemoryTokenStore();
    final auth = _auth(store: store);
    await auth.login('user@example.com', 'password123');
    expect(auth.email, 'user@example.com');
    expect(auth.isSignedIn, isTrue);
    expect(store.token, isNotNull);
    expect(await auth.accessToken(), isNotNull);
  });

  test('short password rejected before any network call', () async {
    final fake = FakeBackend();
    final auth = _auth(fake: fake);
    expect(
      () => auth.login('user@example.com', 'short'),
      throwsA(isA<BackendApiException>()),
    );
    expect(fake.sessions, 0);
  });

  test('restore with no token returns null', () async {
    expect(await _auth().restore(), isNull);
  });

  test('restore with bad token clears the store', () async {
    final store = MemoryTokenStore()..token = 'stale';
    final auth = _auth(store: store);
    expect(await auth.restore(), isNull);
    expect(store.token, isNull);
  });

  test('logout clears state and store', () async {
    final store = MemoryTokenStore();
    final auth = _auth(store: store);
    await auth.login('user@example.com', 'password123');
    await auth.signOut();
    expect(auth.isSignedIn, isFalse);
    expect(store.token, isNull);
  });

  test('http client sends JSON and parses the session', () async {
    var paths = <String>[];
    final client = HttpBackendApiClient(
      httpClient: MockClient((req) async {
        paths.add(req.url.path);
        expect(req.headers['Content-Type'], 'application/json');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['email'], 'user@example.com');
        return http.Response(
          jsonEncode({
            'email': 'user@example.com',
            'accessToken': 'a1',
            'refreshToken': 'r1',
            'expiresInSec': 900,
          }),
          200,
        );
      }),
      baseUrl: 'https://api.example.com',
    );
    final s = await client.login('user@example.com', 'password123');
    expect(paths, ['/auth/login']);
    expect(s.accessToken, 'a1');
    expect(s.expiresAtMs, greaterThan(0));
  });

  test('http client throws typed errors with server message', () async {
    final client = HttpBackendApiClient(
      httpClient: MockClient(
        (req) async =>
            http.Response(jsonEncode({'message': 'wrong password'}), 401),
      ),
      baseUrl: 'https://api.example.com',
    );
    try {
      await client.login('user@example.com', 'password123');
      fail('expected BackendApiException');
    } on BackendApiException catch (e) {
      expect(e.isUnauthorized, isTrue);
      expect(e.message, 'wrong password');
    }
  });
}
