import 'package:flutter_riverpod/flutter_riverpod.dart';

class GoogleAuthAccount {
  const GoogleAuthAccount({this.email});
  final String? email;
}

final googleAccountProvider = StreamProvider<GoogleAuthAccount?>((ref) async* {
  yield null;
});