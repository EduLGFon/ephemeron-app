# Security review (code-level, Phase 10)

Date: 2026-10-29. No Android SDK or devices here; device/store items are
owner checks. This records what was verified in code and what remains.

## Verified in code

- No hardcoded secrets: no API keys, passwords, keystores or tokens in
  source (OAuth client IDs are public identifiers passed via
  `--dart-define`, never committed).
- Tokens: Google OAuth tokens and the backend refresh token live only in
  `flutter_secure_storage` (platform keystore) via `SafeSecureStorage`.
  Access tokens stay in memory. Nothing token-like is written to
  SharedPreferences, Drift, logs or backups (the DB holds no tokens).
- Logging: `AppLogger` caps at 500 lines and the codebase logs no tokens,
  passwords, user ids, calendar or note content.
- Transport: no `http://` URLs in code; Google and backend clients use
  HTTPS only. The backend base URL is empty by default (offline).
- SQL: all queries go through Drift; no string-concatenated SQL. LIKE
  patterns are bound variables; `%`/`_` wildcards in user input are
  stripped by search methods.
- Backend isolation: `backend_api_client.dart`, `backend_sync_api.dart`,
  `backend_sync_engine.dart` and `backend_auth.dart` import no Google code
  and read/write only habit/focus tables. Google outbox entities are
  skipped by the backend engine and vice versa.
- Dependencies: no analytics, crash-reporting, ads or telemetry SDKs.
  Deps are first-party or narrowly scoped (http, google_sign_in,
  flutter_secure_storage, markdown, image, path_provider).
- Android manifest: receivers are `exported=false`; only MainActivity is
  exported. Permissions are limited to alarms, boot/time recovery,
  vibration, notifications and (fixed 2026-10-29) INTERNET for release.

## Fixed in this review

- INTERNET was debug/profile-only: release builds could not reach Google
  or the backend at all. Added to the main manifest.

## Owner checks (need SDK/device/store)

- Release build: `flutter build appbundle`, install, verify Google sync,
  backend sync, and an alarm fires after reboot.
- Rename `com.example.ephemeron` to the real applicationId AND the
  matching `SNOOZE`/`DONE` action strings in `AlarmReceiver.kt` together.
- Play Console: `USE_EXACT_ALARM` declaration (calendar/alarm use case).
- Auto-backup rules: exclude the secure-storage prefs file so tokens never
  leave the device via Google Drive backup; verify the prefs file name for
  the pinned flutter_secure_storage version.
- Confirm backend serves TLS 1.2+ with valid certs; rate limits on.
- Run `flutter pub outdated` + dependency audit before release.
