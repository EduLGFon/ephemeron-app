// Auth providers.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend_auth.dart';
import '../data/google_auth.dart';

final googleAuthProvider = Provider<GoogleAuth>((ref) => GoogleAuth());

final googleAccountProvider = NotifierProvider<GoogleAccountNotifier, String?>(
  GoogleAccountNotifier.new,
);

final googleAccountsProvider =
    NotifierProvider<GoogleAccountsNotifier, List<String>>(
  GoogleAccountsNotifier.new,
);

class GoogleAccountNotifier extends Notifier<String?> {
  @override
  String? build() {
    unawaited(restore());
    return null;
  }

  Future<void> restore() async {
    try {
      state = await ref.read(googleAuthProvider).restore();
      ref.read(googleAccountsProvider.notifier).refresh();
    } catch (_) {}
  }

  Future<void> signIn({bool tasks = false}) async {
    state = await ref.read(googleAuthProvider).signIn(tasks: tasks);
    ref.read(googleAccountsProvider.notifier).refresh();
  }

  Future<void> signOut([String? account]) async {
    await ref.read(googleAuthProvider).signOut(account);
    state = ref.read(googleAuthProvider).email;
    ref.read(googleAccountsProvider.notifier).refresh();
  }

  Future<void> setActive(String email) async {
    await ref.read(googleAuthProvider).setActiveAccount(email);
    state = email;
  }

  void setSignedInEmail(String? email) => state = email;
}

class GoogleAccountsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => const [];
  void refresh() {
    state = ref.read(googleAuthProvider).accounts;
  }
}

final backendAuthProvider = Provider<BackendAuth>((ref) => BackendAuth());

final backendAccountProvider =
    NotifierProvider<BackendAccountNotifier, String?>(
      BackendAccountNotifier.new,
    );

/// Email/password account for habits/focus sync. Holds the email only;
/// tokens stay inside BackendAuth (memory + keystore).
class BackendAccountNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  Future<void> restore() async {
    state = await ref.read(backendAuthProvider).restore();
  }

  Future<void> login(String email, String password) async {
    state = await ref.read(backendAuthProvider).login(email, password);
  }

  Future<void> signUp(String email, String password) async {
    state = await ref.read(backendAuthProvider).signUp(email, password);
  }

  Future<void> signOut() async {
    await ref.read(backendAuthProvider).signOut();
    state = null;
  }
}
