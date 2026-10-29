// Auth providers.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/google_auth.dart';

final googleAuthProvider = Provider<GoogleAuth>((ref) => GoogleAuth());

final googleAccountProvider = NotifierProvider<GoogleAccountNotifier, String?>(
  GoogleAccountNotifier.new,
);

class GoogleAccountNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  Future<void> signIn({bool tasks = false}) async {
    state = await ref.read(googleAuthProvider).signIn(tasks: tasks);
  }

  Future<void> signOut() async {
    await ref.read(googleAuthProvider).signOut();
    state = null;
  }
}
