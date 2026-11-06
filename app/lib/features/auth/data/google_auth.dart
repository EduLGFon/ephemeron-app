// Google sign-in (v7 API on mobile/web): incremental scopes, silent token refresh.
// Supports multiple signed-in accounts simultaneously.
//
// The implementation is split across `part` files under `google_auth/`
// while this file stays the public entry point.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/safe_storage.dart';

part 'google_auth/base.dart';
part 'google_auth/init.dart';
part 'google_auth/sign_in.dart';
part 'google_auth/token.dart';
part 'google_auth/account.dart';

class GoogleAuthException implements Exception {
  GoogleAuthException(this.message);
  final String message;
  @override
  String toString() => 'GoogleAuthException: $message';
}

class GoogleAuth extends _GoogleAuthBase
    with
        _GoogleAuthInit,
        _GoogleAuthSignIn,
        _GoogleAuthToken,
        _GoogleAuthAccount {
  GoogleAuth({super.storage});
}
