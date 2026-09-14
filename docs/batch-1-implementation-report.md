# GradPort Batch 1 implementation report

## Work preserved and resumed

Inspected the dirty working tree and continued the existing partial Batch 1 work rather than restarting. Preserved the previously implemented keyboard scroll helper and all pre-existing Gemini/OCR, Add File, portfolio compiler/export, fonts, dependency-lockfile, and platform registration changes. A SHA-256 comparison confirmed 35 pre-existing files outside the Batch 1 changes remained byte-for-byte unchanged. No files were reset or reverted. No commits, pushes, or deployments were made.

The interrupted work already included the backend OTP/session, password-change, name-validation and profile-choice foundations, plus Flutter auth-form submission guards. The continuation finished Settings integration, Profile dropdowns, Dashboard navigation, Back behavior, validation/error feedback, and verification coverage.

## Issues and resolutions

| Issue | Finding | Implemented behavior |
| --- | --- | --- |
| Keyboard and password eyes | The existing auth scroll helper was already appropriate; password eyes had small tap targets and Settings needed coverage. | Preserved single scroll surfaces; enlarged shared auth password controls, added Show/Hide labels, verified eyes and submit reachability with 540/640-pixel keyboard insets. Settings hides its fixed logout footer while the keyboard is open. |
| Signup bounced back to Login | Verification returned only a user and Flutter deliberately navigated back to Login. | Successful OTP verification atomically consumes the code, activates the account and creates the existing normal session; Flutter persists the refresh token and goes straight to Dashboard with auth routes removed. |
| Numeric personal names | Validation checked length, not numeric characters. | Shared per-platform name validation rejects Unicode numeric characters, permits Unicode letters/marks, spaces, hyphens and straight/curly apostrophes; preserves 2–100-character limits. Backend also normalizes NFC. Numbers show “Names cannot contain numbers.” |
| Profile free typing | Program, year and school all used free-text dialogs. | Program/year dropdowns use server-owned choices. School is read-only; new accounts and empty edit forms default to New Era University. Existing nonempty legacy values are preserved. |
| Blank Dashboard information | Missing optional fields used different wording and the card did not show school. | Real AuthScope data with display-only “Program not set”, “Year level not set”, “School not set”; no placeholders persisted. |
| Dashboard category taps did nothing | Tap callbacks displayed an “Opened” snackbar. | Taps push the existing Files screen with a category filter; the existing ViewFilesScreen displays documents across its folders. Creative Titles filters the existing creative-title folder across categories. No duplicate list or document state. |
| Missing Back controls | Edit Profile relied on an implicitly generated root-style AppBar; pushed Signup lacked a visible Back control. | Explicit Back on Edit Profile and pushed Signup; labeled existing auth Back controls and shared nested Back controls. Root AppBars no longer imply a Back button. |
| Password change did not persist | Settings showed a delayed development-mode success without any backend call. Its logout only navigated, and passwords were trimmed. | Real authenticated password-change endpoint and UI; unmodified password bytes; atomic persistence/revocation; success only after backend confirmation. Settings logout now invokes AuthService.logout. |
| Rapid rate limiting | Submit buttons were disabled, but handler-level guards were missing, allowing IME re-entry. Repeated incorrect credentials legitimately consume existing limits. | In-flight guards on auth and edit forms, separate password-change rate limit, safe 429 message and Retry-After countdown. Existing login/account/IP limits are unchanged; unrelated route groups do not count as login attempts. |
| Inconsistent/raw form errors | Screens could show backend messages or unfiltered field text, or collapse errors into generic failures. | UI allowlist maps validation, credentials, forbidden/conflict, throttling, network/timeout, storage and server failures to safe messages while retaining inputs. |

The mock password screen explains why a supposedly changed password did not work. It did not modify the old hash. The reported failure of both passwords on testers' accounts cannot be proven from source alone; repeated attempts can trigger the existing limiter. Disposable integration tests now prove the required new-password/old-password behavior.

## Final signup and session flow

Sign Up → account created → OTP with the entered email → valid OTP → normal access/refresh session → Dashboard. No extra login and no Back route into signup/OTP.

Invalid codes never authenticate. Code consumption, activation and session creation share a MongoDB transaction; a simulated session-write failure rolls back activation and leaves verification retryable. A pending duplicate with matching credentials returns EMAIL_NOT_VERIFIED without creating another user or resending. Wrong-password/verified duplicates retain the duplicate-account error. Resend remains explicit and cooldown-limited.

Only refresh tokens persist securely. Access tokens remain in memory. The resulting session can restore through the existing refresh/rotation flow.

## Profile choices

The canonical list is backend/src/modules/users/profile-options.ts, returned as data.profileOptions in current-user responses and consumed by Flutter, not a duplicate hardcoded client catalogue.

- Bachelor of Science in Information Technology
- Bachelor of Science in Computer Science
- 1st Year, 2nd Year, 3rd Year, 4th Year
- New Era University (read-only in Flutter)

These two programs are evidenced in the existing repository. A broader approved CICS catalogue was not supplied. Unknown new program/year/school choices are rejected; unchanged legacy stored values remain safe on unrelated edits. Empty program/year values remain allowed. An empty school's edit default is only saved when the user explicitly saves.

## Password-change contract and safeguards

POST /api/v1/auth/password/change requires a valid JWT backed by its active, owner-matching session. Its strict body accepts currentPassword and newPassword only.

The backend verifies the current password, checks the existing 8–128-character uppercase/lowercase/digit policy, hashes with Argon2id, and compare-and-sets the stored hash inside a transaction. The same transaction revokes all user sessions and outstanding password-reset codes/grants. It returns {status: "passwordChanged"} only after commit. Invalid current password returns safe INVALID_CURRENT_PASSWORD; unauthorized, validation and persistence failures never report success.

Flutter clears local auth after success and routes to Login with a password-updated message. Reset completion also clears any local stale session after backend success. Raw passwords are never trimmed, stored or logged; currentPassword log redaction was added. The authenticated endpoint is limited to five requests per 15 minutes per account, separately from login.

No packages, environment variables, migrations, indexes, Atlas permissions or secrets were added/changed for Batch 1. Existing MongoDB transaction support is reused.

## Navigation audit

Added explicit upper-left Back behavior for Edit Profile and pushed Signup. Preserved normal Navigator.pop on Forgot Password, New Password, verification, Change Password, Add File, extracted text/file detail, college report, and portfolio nested screens. Existing shared nested Back buttons now have a standard tooltip. Filtered Files pushes also return naturally to Home. Home, root Files, Profile and Settings do not receive Back buttons.

No portfolio/OCR screen implementation was edited for this audit.

## Tests and verification

| Command/check | Final result |
| --- | --- |
| npm run typecheck | PASS |
| npm run lint | PASS |
| npm run test:unit | PASS: 189 tests, 16 files |
| npm run test:integration | PASS: 56 tests, 7 files |
| npm run build | PASS |
| dart format (22 explicitly selected Batch 1 Dart files only) | PASS |
| Focused Flutter auth/Profile/Home suite | PASS: 58 tests |
| flutter test -r expanded | 135 passed, 1 failed: existing real-local-backend smoke test |
| flutter analyze | 0 errors, 0 warnings, 34 informational style/deprecation diagnostics; exit 1 |
| git diff --check | PASS |

The only full-suite failure is test/api_client_smoke_test.dart:

> Unable to reach the server. Check your connection and try again.
> package:proport_app/services/api_client.dart 173:7 ApiClient._perform

It was independently reproduced. No local API was started and no environment was changed to hide this failure. The existing smoke test specifically expects local storage and console email, which must match its test target.

Added backend coverage for Unicode/numeric names, pending duplicate resumption without resend, no session before/after invalid OTP, transaction rollback, OTP session issuance/restoration, constrained profile choices and legacy preservation, safe projections, authenticated password change, simulated update failure, Argon2id persistence, all-session revocation, logout and new/old password login, and reset grant reuse/persistence. Existing ownership isolation tests pass.

Flutter coverage includes large-inset keyboard/eye behavior, signup/invalid OTP/direct Dashboard/restoration, root navigation history, duplicate IME submission, Retry-After, safe error mapping, change-password success/failure and retained bytes, Program/Year selections, school default, legacy preservation, actual/missing Dashboard data, all six category filters, cross-folder matching, filtered empty state and Back navigation.

Intermediate failures were resolved: old reset-field/school expectations, new test fixture assertions, and cleanup ordering in the new disposable suite. The final database suite passes.

All database writes/cleanup were confined to the existing safeguarded, dynamically named gradport_test_* local replica-set databases. The external-MONGODB_URI refusal and loopback/disposable target guards were preserved. No development/production Atlas data was reset, dropped or modified.

## Exact Batch 1 files changed

This list excludes preserved, unrelated pre-existing dirty files. It includes both resumed Batch 1 work and the completion changes, plus this report.

- backend/README.md
- backend/src/common/logging/logger-options.ts
- backend/src/common/validation/personal-name.ts
- backend/src/database/repositories/one-time-code.repository.ts
- backend/src/database/repositories/session.repository.ts
- backend/src/database/repositories/user.repository.ts
- backend/src/modules/auth/auth.routes.ts
- backend/src/modules/auth/auth.schemas.ts
- backend/src/modules/auth/auth.service.ts
- backend/src/modules/users/profile-options.ts
- backend/src/modules/users/user.routes.ts
- backend/src/modules/users/user.schemas.ts
- backend/src/modules/users/user.service.ts
- backend/tests/auth/batch-one-validation.test.ts
- backend/tests/integration/auth-routes.integration.test.ts
- backend/tests/integration/batch-one-auth.integration.test.ts
- backend/tests/integration/current-user.integration.test.ts
- backend/tests/logging/logger-options.test.ts
- docs/batch-1-implementation-report.md
- lib/screens/auth/forgot_password_screen.dart
- lib/screens/auth/login_screen.dart
- lib/screens/auth/new_password_screen.dart
- lib/screens/auth/signup_screen.dart
- lib/screens/auth/verification_code_screen.dart
- lib/screens/auth/widgets/auth_form_feedback.dart
- lib/screens/auth/widgets/auth_text_field.dart
- lib/screens/files/files_screen.dart
- lib/screens/files/view_files_screen.dart
- lib/screens/home/home_screen.dart
- lib/screens/profile/edit_profile_screen.dart
- lib/screens/profile/profile_screen.dart
- lib/screens/settings/change_password_screen.dart
- lib/screens/settings/widgets/password_field.dart
- lib/services/auth_service.dart
- lib/services/form_validation.dart
- lib/services/profile_options.dart
- lib/widgets/grad_app_bar.dart
- test/auth_keyboard_scroll_test.dart
- test/batch_one_auth_test.dart
- test/home_screen_test.dart
- test/profile_screen_test.dart

## Remaining manual checks and limitations

- Test the updated backend and Android APK together: signup → emailed OTP → Dashboard → restart/session restore.
- On real devices, test keyboard/eye controls, large font settings, back navigation, profile selections and each category filter.
- Change a password, confirm forced sign-in with the new password and rejection of the old password; verify forgot/reset separately.
- Re-run the existing readiness smoke test against a running local/console backend. Its current failure is not hidden or skipped.
- Review/confirm whether the evidenced IT/CS catalogue is the full approved CICS program list.
- Remaining analyzer infos are style/deprecation notices; unrelated cleanup was not performed.
- No APK build, real email delivery, production rollout, commit or push was performed in this batch. Await approval before release actions.

