// Auth providers.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend_auth.dart';
import '../data/google_auth.dart';

final googleAuthProvider = Provider<GoogleAuth>((ref) => GoogleAuth());

final googleAccountProvider = NotifierProvider<GoogleAccountNotifier, String?>(
  GoogleAccountNotifier.new,
);

class GoogleAccountNotifier extends Notifier<String?> {
  @override
  String? build() {
    unawaited(restore());
    return null;
  }

  /// Restores a previous sign-in (tokens + email live in secure storage).
  /// Called on startup and safe to call again after sign-in.
  Future<void> restore() async {
    try {
      state = await ref.read(googleAuthProvider).restore();
    } catch (_) {
      // No stored session: stay signed out.
    }
  }

  Future<void> signIn({bool tasks = false}) async {
    state = await ref.read(googleAuthProvider).signIn(tasks: tasks);
  }

  Future<void> signOut() async {
    await ref.read(googleAuthProvider).signOut();
    state = null;
  }

  void setSignedInEmail(String? email) => state = email;
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
