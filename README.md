# GradPort mobile app

GradPort is a Flutter Android/iOS client backed by the Fastify API in
[`backend/`](backend/README.md). Authentication uses short-lived access tokens
in memory and a rotating refresh token in platform secure storage.

## API URL

`API_BASE_URL` is a build-time value. Debug builds default to
`http://127.0.0.1:3000`, which is convenient for the iOS simulator and Windows
smoke tests. Android emulator builds normally use the host alias:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

For a physical development device, supply an explicit LAN development URL or a
trusted HTTPS tunnel. The Android and iOS debug configurations permit local
HTTP development without weakening release networking.

Release builds require an explicit deployed `https://` API URL and reject
missing, malformed, cleartext, or loopback values when the app starts:

```powershell
flutter build appbundle --release `
  --dart-define=API_BASE_URL=https://api.example.com
```

Never place MongoDB credentials, JWT secrets, code peppers, email-provider
credentials, or other backend secrets in `--dart-define` or in Flutter files.

## Verification

```powershell
flutter analyze
flutter test test/api_client_test.dart test/auth_service_test.dart test/widget_test.dart
flutter test test/api_client_smoke_test.dart -r expanded
```

The smoke test intentionally calls a running local backend. Backend commands,
disposable-database safeguards, and auth/deployment notes are documented in
[`backend/README.md`](backend/README.md).

## Deployment boundary

Android and iOS are the production targets. A deployed HTTPS backend,
production SMTP/provider configuration, final application/bundle identifiers, Android
signing and AAB preparation, and App Store/TestFlight signing and metadata are
separate deployment tasks. The current API contract and token/email
abstractions are designed so those tasks do not require redesigning the auth
flow.
