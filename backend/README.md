# GradPort Backend

This directory contains GradPort's Fastify and MongoDB backend. It includes the persistence foundation and the versioned authentication, current-user, portfolio, and document APIs used by the Flutter Android and iOS clients.

Authenticated PDF/JPEG/PNG uploads use private local object storage in development and private Cloudflare R2 storage in production. Local OCR and embedded PDF text extraction read through the same storage abstraction.

## Requirements

- Node.js 22.15 or newer and below Node 25
- npm 10 or newer
- Internet access for npm installation and the first disposable MongoDB test-binary download

Docker is not required. Local health checks may use the mock database, but authentication requires a connected MongoDB database. Local storage remains the development storage adapter; email can use the console or SMTP adapter.

```powershell
Set-Location backend
npm ci
# Configure the ignored .env.development.local file, then:
npm run dev:atlas
```

Health/readiness remain unchanged:

```text
GET /health
GET /ready
```

Authentication is exposed under `/api/v1/auth`:

```text
POST /api/v1/auth/register
POST /api/v1/auth/email-verification/verify
POST /api/v1/auth/email-verification/resend
POST /api/v1/auth/login
POST /api/v1/auth/password-reset/request
POST /api/v1/auth/password-reset/verify
POST /api/v1/auth/password-reset/complete
POST /api/v1/auth/password/change
POST /api/v1/auth/refresh
POST /api/v1/auth/logout
```

Authenticated profile access is exposed under `/api/v1/users`:

```text
GET /api/v1/users/me
PATCH /api/v1/users/me
```

Both routes require a valid access token backed by its active server-side session. The PATCH route accepts only `firstName`, `lastName`, `program`, `yearLevel`, and `school`; email changes and client-selected user IDs are not accepted.

Email verification now returns the normal `{ user, tokens }` session payload: the code consumption, account activation, and session creation commit together. Flutter securely persists only the refresh token and opens Dashboard without an extra login. A pending duplicate registration with matching credentials returns `EMAIL_NOT_VERIFIED` without issuing tokens or automatically resending a code.

Authenticated `POST /api/v1/auth/password/change` accepts only `currentPassword` and `newPassword`. It verifies the current password, atomically replaces its Argon2id hash, revokes all sessions and outstanding reset codes/grants, then returns `{ status: "passwordChanged" }`. Flutter clears its session and asks the user to sign in with the new password. Password whitespace is never trimmed. This endpoint has a separate five-per-15-minute account limit; existing login limits remain unchanged.

Current-user responses also include `data.profileOptions`, sourced from `src/modules/users/profile-options.ts` and shared by server validation and Flutter dropdowns. The evidenced programs are Bachelor of Science in Information Technology and Bachelor of Science in Computer Science; years are 1st through 4th Year. New registrations default to New Era University. School is read-only in the app, and unchanged legacy values are preserved on unrelated edits. Names accept Unicode letters/marks, spaces, hyphens and apostrophes, reject numbers, and retain the existing 2–100-character bounds. Dashboard placeholders are display-only, and category taps filter the existing authenticated Files list.

Authenticated document access is exposed under `/api/v1/documents`:

```text
GET    /api/v1/documents/categories
GET    /api/v1/documents
POST   /api/v1/documents
GET    /api/v1/documents/:documentId
GET    /api/v1/documents/:documentId/content
GET    /api/v1/documents/:documentId/ocr
POST   /api/v1/documents/ocr-preview
POST   /api/v1/documents/:documentId/ocr
PATCH  /api/v1/documents/:documentId/ocr
DELETE /api/v1/documents/:documentId
```

Upload uses `multipart/form-data` with one `file` part plus `categoryKey`, `folderKey`, `title`, and `documentDate` (`YYYY-MM-DD`). `description` and `reflection` are optional. Valid PDF, JPG/JPEG, and PNG files are limited to 15 MB. Extension, declared MIME type, and file signature must agree. The user ID is always derived from the authenticated access token; client-supplied ownership fields are rejected.

Access tokens are HS256 JWTs valid for 15 minutes. Opaque refresh tokens are valid for 30 days, are stored only as SHA-256 hashes, rotate on every refresh, and revoke their token family when a replaced token is replayed. Passwords use Argon2id. Verification/reset codes contain six digits, expire after ten minutes, and are stored only as keyed hashes.

## MongoDB storage boundary

MongoDB stores account records, session/code records, category and report definitions, college-report answers, and document metadata. A document record contains an owner, category/folder, file name, MIME type, file kind, extension, size, checksum, and private `objectKey` reference. After extraction, its nested `ocr` record stores the processing status, immutable extracted `rawText`, user-editable `reviewedText`, engine name, and timestamps.

MongoDB must never contain uploaded file bytes, `Buffer` payloads, Base64 data, data URLs, GridFS identifiers, GridFS buckets, or file chunks. The repository and schema layers reject these values. Actual files are stored beneath `LOCAL_STORAGE_PATH` by the development adapter or in a private Cloudflare R2 bucket by the production adapter. Generated object keys, not filesystem paths, are stored in MongoDB and remain internal. The content endpoint and `DocumentService.openContent()` remain the file-read boundary, so document and OCR APIs do not depend on the selected storage driver.

## Document text extraction

Image OCR runs locally with Tesseract.js and the English trained-data npm package. Language data is installed with backend dependencies and is read locally; the API does not download OCR models at request time. JPEG and PNG dimensions are validated before OCR, with a 25-megapixel limit, and extraction has a 45-second backend timeout.

PDF.js extracts embedded text from PDFs without rendering pages. PDFs are limited to 100 pages and OCR text is limited to 200,000 characters. Password-protected PDFs are rejected. Image-only/scanned PDFs return `SCANNED_PDF_OCR_NOT_SUPPORTED`; rasterizing them is intentionally deferred to avoid system-executable and native rendering dependencies.

OCR starts synchronously with `POST /api/v1/documents/:documentId/ocr`. An atomic, expiring processing lease prevents duplicate concurrent work for the same document. `GET` reloads the persisted result and `PATCH` accepts only `reviewedText`; clients cannot replace `rawText` or ownership/security fields. Every operation derives ownership from the access token and returns the same safe document-not-found response for another user's ID. File contents and extracted text are never written to application logs.

Existing document records require no data migration: a missing `ocr` field is returned as `not_processed`, and OCR adds no index. Existing runtime `find`/`update` permissions on `documents` are sufficient.

Add a File can request `POST /api/v1/documents/ocr-preview` with one multipart `file` and no text fields. This authenticated preview uses the existing file validation, OCR engine and limits, shares the per-user OCR rate limit, and persists neither an object nor a document. It returns the standard `{data:{ocr:{status:"ready",rawText,reviewedText,engine,metadataSuggestions}},meta:{requestId}}` envelope. Existing owner-scoped OCR GET/POST/PATCH responses also include `metadataSuggestions` when ready, computed from `reviewedText` (including an intentionally empty review), falling back to `rawText` only when no review exists.

Optional suggestion fields remain `categoryKey`, `folderKey`, `title`, `documentDate` (`YYYY-MM-DD`), and `description`; Reflection is never generated. The deterministic parser remains the fallback. It uses explicit subject markers, known certificate categories/folders, and conservative date parsing. Missing, impossible, conflicting, or ambiguous MM/DD versus DD/MM dates are omitted. No current date or filename is substituted.

Selecting a supported JPEG/PNG/PDF in Flutter automatically starts the preview, shows the filename and **Reading document...**, and fills empty metadata fields. **Apply AI suggestions** (or **Apply OCR suggestions** for basic results) is an explicit replacement action. Manual edits and Reflection are protected during automatic prefilling. A new file clears only earlier automatic values, starts one new preview, and ignores late results/errors from the old file. Preview failure does not prevent manual upload. Stored-file extraction/review continues through the existing OCR endpoints. No database schema, seed, index or permission change is needed.

### AI-Assisted Academic Document Classification and Metadata Recommendation

OCR is text extraction; Google Gemini is the third-party AI component. GradPort does not train or develop a custom machine-learning model.

```text
Authenticated file selection → existing /api/v1/documents/ocr-preview
→ local OCR → bounded text → Gemini → backend validation
→ transient metadataSuggestions → user reviews/edits → existing upload/save
                         ↘ Gemini unavailable: deterministic parser fallback
```

Enable the feature only in the backend's ignored runtime environment or deployment secret store:

```dotenv
AI_PROVIDER=gemini
GEMINI_API_KEY=<your secret API key; never commit>
GEMINI_MODEL=gemini-3.5-flash
GEMINI_TIMEOUT_MS=20000
```

`AI_PROVIDER=none` is the default and disables all external AI calls, preserving the basic parser. With `gemini`, a nonempty key and model ID are required; startup fails with sanitized variable-name-only errors if configuration is incomplete. The timeout defaults to 20 seconds and allows 1–30 seconds. Maintenance/database-only configuration does not require AI settings. The example model is configurable: confirm availability in your Google project and select a text model supporting [Gemini structured output](https://ai.google.dev/gemini-api/docs/generate-content/structured-output) from the [current model catalog](https://ai.google.dev/gemini-api/docs/models). No SDK or other new package is required; the provider uses Node's existing `fetch` support and the documented [generateContent REST API](https://ai.google.dev/api/generate-content).

Implementation boundaries:

- `GeminiMetadataProvider` makes one HTTPS request, puts the key only in `x-goog-api-key` (not the URL), disallows redirects, bounds the response to 64 KiB, and aborts on timeout. No automatic retries, file uploads to Google, search tools, function calls, or model-authored executable code.
- `AiMetadataService` prefers `reviewedText` over `rawText`, including an explicitly empty review. It normalizes whitespace while preserving line boundaries, caps input at 12,000 characters, and omits obvious credential-assignment lines. No user/session objects, auth headers/tokens, filenames, file bytes, or backend secrets enter the prompt.
- Gemini receives only OCR text and the current active category/folder list. OCR text is explicitly treated as untrusted data, not instructions. The model requests null/empty for uncertainty and never Reflection.
- The internal JSON schema requires `content`, `folder`, `classificationEvidence`, `title`, `date`, and `descriptionQuotes`. Runtime service validation checks the same finite shape/types and rejects missing/extra fields (including Reflection). Unknown category/folder values are omitted, not created. Matching uses only case/whitespace normalization of actual current names/keys and validates folder membership in the selected category.
- Classification requires an exact source excerpt as evidence. Titles (max 250 characters) must occur in OCR, not be a detected recipient name. Description is up to three short, exact source excerpts joined with an em dash (under 2,000 characters), not unverified generated prose. Markup and overlong values are rejected, controls/whitespace normalized. Dates must be valid, unambiguous, source-supported document/event dates according to the existing conservative parser; birth/expiry dates are excluded.
- AI semantics and OCR accuracy cannot be guaranteed by evidence matching. Unrecognized date formats, translated/paraphrased titles and descriptions are intentionally omitted rather than guessed. The user must review the editable recommendations.
- Successful preview responses additionally include `metadataAnalysis: {source: "gemini" | "rules" | "none", aiStatus: "success" | "unavailable" | "disabled" | "not_needed"}`. Internal evidence/provider output is not returned or persisted. Flutter labels only genuine validated Gemini results **AI suggested from document**. When AI fails, basic results are labeled as fallback, not AI.
- Timeout, HTTP errors (including quota errors), blocked/truncated or malformed output, and unusable suggestions fall back to the existing deterministic parser. If neither can help, OCR still returns and manual entry remains possible. Gemini does not affect `/health` or `/ready` and is not called by ordinary document GET, saved OCR GET/review, or app rebuilds.
- Existing authenticated per-user preview/extraction limit is shared (default 5/minute). Each file selection makes one analysis request. Flutter reserves 120 seconds for upload/cold start + up to 45-second OCR + up to 30-second AI; normal API timeouts are unchanged. This does not guarantee completion on an overloaded/free host. Stale results/errors cannot overwrite newer successful analysis, and network timeouts are distinguished from OCR failures.
- The AI layer logs only locally generated diagnostic codes, request ID, provider/model, HTTP status when known, and latency. It never logs raw provider errors/messages, OCR text, rejected metadata, keys or tokens. Logger redaction additionally covers Gemini key fields/headers and OCR/request/candidate payload fields. Recommendations are not persisted until the user saves; previews do not persist OCR text either.

#### Gemini request and safe fallback diagnostics

The provider uses `POST https://generativelanguage.googleapis.com/v1beta/models/<configured-model>:generateContent`, JSON `contents` and `systemInstruction`, and `generationConfig.responseMimeType="application/json"` with `responseJsonSchema`. It does not mix in the separate OpenAPI `responseSchema` format. Nullable strings, required fields, `additionalProperties:false`, and the three-quote bound remain enforced by backend validation as well as the requested schema. See the [generateContent configuration reference](https://ai.google.dev/api/generate-content#v1beta.GenerationConfig).

`candidateCount` is omitted (one candidate is the default): [Gemini 3.5 migration guidance](https://ai.google.dev/gemini-api/docs/whats-new-gemini-3.5#migrate-from-gemini-25) flags this option as unsupported for Gemini 3.x. Gemini 3 model IDs use `thinkingConfig.thinkingLevel="LOW"` for this bounded extractive task, rather than spending the 20-second deadline on the model's default thinking effort. Older model IDs do not receive this Gemini 3 option. The 4,096-token output cap, configured timeout, prompts and grounding policy remain unchanged. This removes a request compatibility risk; a successful plain-text key/model smoke test alone does not establish that the application's structured request succeeds.

Render logs now identify the result of each attempted AI preview with the same server-generated `requestId` as the API response. `AI_SUCCESS` is emitted only after useful grounded metadata passes validation; all failure codes below preserve deterministic fallback and do not become API errors:

| Diagnostic code | Meaning / next check |
| --- | --- |
| `AI_HTTP_400` | The structured request was rejected. Check request/model option compatibility, not just the API key. |
| `AI_HTTP_401`, `AI_HTTP_403`, `AI_HTTP_404` | Provider authentication, permission or resource lookup failure respectively; verify deployed configuration privately. |
| `AI_HTTP_429`, `AI_HTTP_5xx` | Quota/rate limit or provider failure. Actual numeric status is in the code and `httpStatus`. |
| `AI_TIMEOUT` | Configured deadline exceeded while fetching headers or body; request is aborted and body cleanup attempted. |
| `AI_PROVIDER_ERROR` | Network/transport or other unexpected provider failure. No raw exception is retained. |
| `AI_INVALID_JSON`, `AI_INVALID_RESPONSE`, `AI_RESPONSE_TOO_LARGE` | Unparseable JSON, invalid candidate envelope, or response beyond 64 KiB. |
| `AI_RESPONSE_TRUNCATED`, `AI_RESPONSE_BLOCKED` | Token-limit termination or provider safety/content blocking; never accept partial output. |
| `AI_SCHEMA_VALIDATION_FAILED` | Output does not match the strict metadata object (including prohibited extra fields such as Reflection). |
| `AI_GROUNDING_REJECTED` | No usable metadata survives the existing evidence/category/date checks; uncertain/null-only responses also use fallback. |

To diagnose an actual APK fallback, correlate the preview response's request ID with one of these log codes after deploying this backend. Do not enable logging of Gemini error bodies or OCR payloads to investigate it. Tests use fake transports only; live Render key/model compatibility, latency, and the original failing document still need deployment verification.

Privacy/cost: OCR text can contain personal document information and is sent to Google when AI is enabled. Credential-line filtering is defense-in-depth, not a general PII scrubber. Use only appropriate demo documents and disclose third-party processing before production use. Review the provider's current data-use/retention terms and configure project quotas/billing alerts and a restricted API key. Existing limits are process-local; a multi-instance deployment needs the existing rate-limit architecture's shared store. Tests use fake providers/transports and never spend API quota or send document content to Google.

Suggested technical description: “GradPort uses a third-party generative AI service through an API for AI-assisted academic document classification and metadata recommendation. The system does not train or develop a custom machine-learning model. OCR first extracts document text, after which the AI service analyzes the extracted text and recommends structured metadata that is validated by the GradPort backend before being presented to the user.”

Current seeded Content → Folder choices (only active entries returned by the repository are eligible):

| Content | Folders |
| --- | --- |
| Curriculum Vitae | Creative Title; Curriculum Vitae |
| Scholastic Record | Creative Title; Unofficial TOR with Reflections |
| Certificates | Creative Title; Seminars; Other Seminars; Trainings |
| Accomplishments | Creative Title; Thesis/Capstone; Case Studies; Projects; Assessments |
| Other Achievements | Creative Title; Projects |
| College Report | College Report |

The existing folder name “Unofficial TOR with Reflections” does not authorize generating Reflection text; that form field always stays manual.

Manual acceptance after you configure Gemini (not performed by automated tests): select the certificate fixture, check Certificates / Trainings / activity title / 2026-09-14 / grounded description, confirm the AI label and blank Reflection, then edit and save. Try another file, an unavailable provider, and no connectivity. Confirm manual edits survive and upload stays available. The preview is a single response, so the lightweight reading indicator covers both OCR and AI; it does not pretend to report live stage progress.

### Saved portfolio and profile UX

Home now exposes **My Portfolios** alongside its existing Generate Portfolio action. **Save Portfolio** uses the existing owner-scoped create endpoint and server-returned record. Confirmation says **Saved to My Portfolios**, with **View Portfolio** and **Back to My Portfolios**; viewing retrieves the saved record, and the same list reloads it after restart/login. The saved object currently contains title-page information, not an assembled document. PDF/DOCX generation/download is not implemented; the active flow no longer claims a successful export. No duplicate history, ownership system, or database migration was introduced.

Profile shows **Program not set**, **Year level not set**, and **School not set** only for blank display values. These strings are never inserted into the editable model or MongoDB. Real saved values and the authenticated email remain authoritative.

Normal repository results never contain `passwordHash`, `refreshTokenHash`, or `codeHash`, including create and update results. Purpose-specific authentication lookups are narrow and their sensitive records must never cross the service boundary.

## Manual Atlas development setup

No code or command in this repository creates Atlas resources. Complete these steps manually in the Atlas UI:

1. Enable MFA and create a development-only project named `GradPort Development`.
2. Create a Free cluster named `gradport-dev` in the closest available region. Do not load sample data.
3. Add only the current public IP as a temporary `/32` network-access entry. Never use `0.0.0.0/0`.
4. Create the custom roles and users below, scoped only to database `gradport_dev` and cluster `gradport-dev`.

### `gradportDevRuntime` custom role

Grant `find`, `insert`, `update`, and `remove` on:

- `users`
- `sessions`
- `one_time_codes`
- `documents`
- `college_reports`
- `portfolios`

Grant `find` only on:

- `document_categories`
- `report_templates`

Create user `gradport_dev_app` with only this role. Restrict it to `gradport-dev`.

### `gradportDevMaintainer` custom role

Configure this as a standalone least-privilege role; it does not need to inherit
`gradportDevRuntime`. In Atlas, grant the following actions only on database
`gradport_dev` and the named collection resources:

| Atlas actions | Collections | Used by |
| --- | --- | --- |
| `FIND`, `INSERT` | `_gradport_migrations` | Read migration status and append applied-migration records |
| `FIND`, `INSERT`, `UPDATE`, `REMOVE` | `_gradport_migration_lock` | Acquire the expiring migration lock with an upsert and release it |
| `CREATE_INDEX`, `LIST_INDEXES` | `users`, `sessions`, `one_time_codes`, `portfolios`, `document_categories`, `documents`, `report_templates`, `college_reports` | Apply migrations 001/002 and verify their indexes |
| `FIND`, `INSERT`, `UPDATE` | `document_categories`, `report_templates` | Verify and idempotently upsert reference-data seeds |

`db:migrate:status` needs only `FIND` on `_gradport_migrations`.
`db:verify` additionally needs `LIST_INDEXES` on each of the eight application
collections and `FIND` on `document_categories` and `report_templates`; it does
not write data. `db:migrate` uses `CREATE_INDEX`, appends the migration ledger,
and acquires/releases the lock. `db:seed` uses the seed-collection actions shown
above.

The current commands do not issue `listCollections` or an explicit
`createCollection` operation. MongoDB's `createIndexes` command can create a
missing collection as part of the index operation, so its collection-scoped
`CREATE_INDEX` privilege is the required migration grant. Do not add
database-wide `LIST_COLLECTIONS` or `CREATE_COLLECTION` merely for these
commands.

Do not grant `dropCollection`, `dropIndex`, `dbAdmin`, `atlasAdmin`, or any-database permissions.

Create temporary user `gradport_dev_maintainer` with this role, restrict it to `gradport-dev`, and set it to expire within seven days.

Official references:

- [Atlas database users](https://www.mongodb.com/docs/atlas/security-add-mongodb-users/)
- [Atlas custom roles](https://www.mongodb.com/docs/atlas/security-add-mongodb-roles/)
- [Atlas IP access lists](https://www.mongodb.com/docs/atlas/security/ip-access-list/)

## Local secret files

Create these files manually. They are ignored by Git and must never be shared or committed:

```powershell
Copy-Item .env.example .env.development.local
Copy-Item .env.maintenance.example .env.maintenance.local
git check-ignore -v .env.development.local .env.maintenance.local
```

Place the runtime user's URI in `.env.development.local` and the temporary maintainer URI in `.env.maintenance.local`. Use Atlas `mongodb+srv` connection strings, URL-encode special password characters, and keep `MONGODB_DB_NAME=gradport_dev`.

Starting the API outside `NODE_ENV=test` also requires two independent random values of at least 32 bytes:

```text
AUTH_JWT_SECRET=<random signing secret>
AUTH_CODE_PEPPER=<different random OTP pepper>
```

Startup fails with a configuration error when either value is missing or too short. Generate them locally and keep them only in the ignored runtime secret file; never commit them, reuse the MongoDB password, or put them in Flutter. Database-only commands use a separate database configuration loader and do not require these API secrets.

Set `CONSOLE_EMAIL_PREVIEW=true` only for explicit local development when a verification/reset code must be read from the backend console. It defaults to false and is rejected in production. API responses and MongoDB records never expose plaintext codes.

## Email delivery

`EMAIL_DRIVER=console` remains the safe local fallback. It does not deliver mail. Message contents appear in logs only when `CONSOLE_EMAIL_PREVIEW=true`, which production configuration rejects.

For real delivery, set `EMAIL_DRIVER=smtp` and provide every value below through the ignored runtime environment file or deployment secret store:

```text
SMTP_HOST=<SMTP hostname>
SMTP_PORT=<SMTP port>
SMTP_SECURE=<true or false>
SMTP_USER=<SMTP account>
SMTP_PASS=<SMTP password or app password>
EMAIL_FROM=<verified sender address>
```

Use `SMTP_SECURE=true` for implicit TLS, normally on port 465. Use `SMTP_SECURE=false` for STARTTLS, normally on port 587; GradPort requires the connection to upgrade to TLS before authenticating. TLS certificate verification is never disabled.

For a Gmail sending account, use `smtp.gmail.com` with either port 465/secure true or port 587/secure false. Use a Google App Password or another SMTP credential authorized by the account rather than a normal Google password, and use an `EMAIL_FROM` address the account is permitted to send as. SMTP delivery can send to Gmail and other standards-compliant recipients.

SMTP mode never logs message contents, OTPs, SMTP credentials, or provider error details. Startup fails with a sanitized configuration error if a required SMTP setting is missing or malformed. `/ready` verifies SMTP connectivity/authentication without sending an email and reports the existing `email` readiness check as `up` or `down`. Delivery failures use the existing `EMAIL_UNAVAILABLE` response; forgot-password responses remain enumeration-safe.

For Render, use Brevo's HTTPS transactional-email API because free web services do not provide a dependable SMTP-port path. Set `EMAIL_DRIVER=brevo` and provide a verified sender:

```text
BREVO_API_KEY=<deployment secret>
BREVO_FROM_EMAIL=<verified sender address>
BREVO_FROM_NAME=GradPort
```

The Brevo adapter sends the same text and HTML verification/reset messages through `EmailSender`; it does not change code generation, hashing, expiry, cooldowns, attempts, or API responses. `/ready` validates the API credential through Brevo's account endpoint without sending mail. Provider errors are reduced to the existing safe `EMAIL_UNAVAILABLE` behavior, and neither API keys nor OTP contents are logged.

The files are loaded only by explicit Atlas/database npm commands. Never pass a URI on a command line, print it, or add it to tracked documentation.

## Migrations and seeds

Mongoose automatic index creation remains disabled. `001_initial_indexes` creates the 17 named indexes declared by the seven schemas and records its checksum in `_gradport_migrations`. An expiring lock prevents concurrent migration execution.

Migrations are forward-only. No rollback, index-drop, collection-drop, truncate, or database-reset command exists.

Seeds insert the six category definitions and `college-engagement-v1` using stable upsert keys and `$setOnInsert`. They never delete or overwrite data, require current migrations, and fail if stored seed content has drifted.

Mutating database commands require explicit confirmation. Read-only diagnostics, migration status,
and verification still validate the exact database and allowed access mode, but do not require the
mutation confirmation flag:

```powershell
npm run db:ping
npm run db:migrate -- --confirm-database=gradport_dev
npm run db:migrate:status
npm run db:seed -- --confirm-database=gradport_dev
npm run db:verify
```

`db:ping` uses runtime credentials. Migration, seed, status, and verification commands use the temporary maintenance credentials. Output is intentionally limited to the database name, statuses, counts, and elapsed time.
Maintenance environment files contain only database configuration; authentication, email, storage,
proxy, and other API-runtime settings are neither loaded nor required by these commands.

To check application readiness against Atlas:

```powershell
npm run dev:atlas
Invoke-RestMethod http://127.0.0.1:3000/health
Invoke-RestMethod http://127.0.0.1:3000/ready
```

Stop with `Ctrl+C` to close Fastify and MongoDB gracefully.

## Local verification

```powershell
npm run typecheck
npm run lint
npm run test:unit
npm run test:integration
npm run build
```

Integration tests start a disposable, loopback-only MongoDB 8.0.29 replica set. They refuse to start if an external `MONGODB_URI` is present and verify the generated database name before deleting it. The first run downloads and caches the MongoDB binary and can require substantial bandwidth and disk space.

## Reverse proxy and rate-limit boundary

`TRUST_PROXY=false` is the safe default for local/direct traffic. When a deployment is placed behind a reverse proxy, set `TRUST_PROXY` only to the exact trusted hop count or a comma-separated list of the proxy IP addresses/CIDRs. The configuration rejects `TRUST_PROXY=true` and wildcard trust.

Never trust arbitrary `Forwarded` or `X-Forwarded-For` headers. Fastify's `request.ip` and all IP rate-limit keys are reliable only after the real proxy chain is restricted correctly. If the API is horizontally scaled, configure the rate-limit plugin with a shared production store so limits apply across every replica; the current local fixed-window account limiter is process-local.

For the current single Render web-service topology, set `TRUST_PROXY=1`. This trusts only the immediate Render proxy hop; it does not unconditionally trust the full forwarded chain. Reconfirm the hop count with a controlled deployment test if another CDN or proxy is added. Keep `TRUST_PROXY=false` everywhere the API receives direct traffic.

Existing authentication limits remain: registration 5/hour/IP, login 10/15 minutes/IP plus 5 failed attempts/15 minutes/normalized email, verification/reset delivery 10/hour/IP plus 3/hour/normalized email, and refresh 30/minute/IP. Cloud deployment adds authenticated per-user limits of 10 document uploads/minute and 5 OCR starts/minute. Normal GET traffic is not globally throttled, OTP attempt limits and resend cooldowns remain unchanged, and each document still has its atomic OCR lease.

## Render + R2 + Brevo demo deployment

Use these Render web-service settings:

```text
Service type: Web Service
Name: gradport-api
Region: Singapore
Branch: main
Root Directory: backend
Build Command: npm ci && npm run build
Start Command: npm start
Compute: Free
Health Check Path: /ready
Auto-Deploy: On Commit
```

Production configuration defaults `HOST` to `0.0.0.0` and reads Render's injected `PORT`; do not hardcode either a service URL or port. Local development continues to default to `127.0.0.1:3000`. `npm start` runs the built `dist/src/server.js` output.

Set the following Render environment variables. Values marked secret belong only in Render's secret environment-variable store. Do not copy them into GitHub, Flutter, source files, or logs.

```text
NODE_ENV=production
LOG_LEVEL=info

DATABASE_DRIVER=mongodb
DATABASE_ENVIRONMENT=development
DATABASE_ACCESS_MODE=runtime
MONGODB_URI=<secret: least-privilege runtime user URI>
MONGODB_DB_NAME=gradport_dev
MONGODB_SERVER_SELECTION_TIMEOUT_MS=10000
MONGODB_CONNECT_TIMEOUT_MS=10000
MONGODB_MAX_POOL_SIZE=10

AUTH_JWT_SECRET=<secret: independent random value, at least 32 bytes>
AUTH_JWT_ISSUER=gradport-api
AUTH_JWT_AUDIENCE=gradport-mobile
AUTH_CODE_PEPPER=<secret: different random value, at least 32 bytes>
AUTH_ACCESS_TOKEN_TTL_SECONDS=900
AUTH_REFRESH_TOKEN_TTL_SECONDS=2592000
AUTH_CODE_TTL_SECONDS=600
AUTH_RESET_GRANT_TTL_SECONDS=600
AUTH_CODE_RESEND_COOLDOWN_SECONDS=60
AUTH_CODE_MAX_ATTEMPTS=5

EMAIL_DRIVER=brevo
CONSOLE_EMAIL_PREVIEW=false
BREVO_API_KEY=<secret>
BREVO_FROM_EMAIL=<verified sender address>
BREVO_FROM_NAME=GradPort

STORAGE_DRIVER=r2
R2_ENDPOINT=<HTTPS S3 endpoint for the R2 account>
R2_ACCESS_KEY_ID=<secret>
R2_SECRET_ACCESS_KEY=<secret>
R2_BUCKET=<private bucket name>
R2_REGION=auto

TRUST_PROXY=1
READY_CHECK_TIMEOUT_MS=5000
OCR_MAX_CONCURRENT_JOBS=1
DOCUMENT_UPLOAD_RATE_LIMIT_MAX=10
DOCUMENT_OCR_RATE_LIMIT_MAX=5
```

Render supplies `PORT` automatically, and production supplies the safe `0.0.0.0` host default, so neither needs a dashboard override. Production startup rejects a mock database, local storage, console/SMTP email, a loopback-only bind, missing auth secrets, and incomplete R2/Brevo configuration.

Create a private R2 bucket and an Object Read & Write API token scoped only to that bucket. Use the S3 endpoint shown by Cloudflare, the generated access-key pair, and region `auto`. Do not enable public bucket access. The adapter uses `PutObject`, `GetObject`, `HeadObject`, `DeleteObject`, and `HeadBucket`; tests inject a fake transport and never contact Cloudflare. Failed metadata persistence still deletes the uploaded object, document deletion still deletes its object, and MongoDB continues to store no file bytes.

Before starting Render, create the service and copy its complete outbound CIDR list from **Connect → Outbound**. Add only those ranges to the Atlas Network Access list, validate `/ready`, then remove any temporary `0.0.0.0/0` entry. Render must use the existing least-privilege runtime database user, never the temporary maintenance account. Do not run migrations as part of deployment; migrations 001 and 002 remain unchanged.

The English Tesseract trained data and PDF.js character-map/font assets are production dependencies under `node_modules`, so `npm ci` installs them during Render's build and OCR performs no language-data download at runtime. Production runs one local OCR job at a time for the Free plan's 0.1 CPU/512 MB limit. The existing 15 MiB file, 25 megapixel image, 100-page PDF, 200,000-character text, 45-second extraction, 90-second lease, and scanned-PDF limitation remain unchanged. Expect cold starts and slower image OCR on Free compute; upgrade the instance if demo latency or memory pressure is unacceptable.

### Manual cloud acceptance

After the first successful deploy:

1. Open `GET https://<service>.onrender.com/ready` and confirm database, storage, and email are all `up`.
2. Register a new disposable demo user and receive its verification OTP through Brevo.
3. Verify, log in, load/edit the current-user profile, and create/edit a portfolio.
4. Upload one small PDF and one small JPEG/PNG; confirm both remain available after a Render restart/redeploy.
5. Run OCR on the image and a text-based PDF, edit/save reviewed text, reload it, and confirm a scanned PDF returns `SCANNED_PDF_OCR_NOT_SUPPORTED`.
6. Restart/reopen the Android app, confirm refresh-token restoration, then log out and log back in.
7. Inspect Render logs for only safe request IDs/statuses—never OTPs, document text, object keys, or provider credentials.

### Android demo APK

The release manifest allows Internet access and rejects cleartext HTTP; only the debug manifest permits local cleartext development. Flutter release configuration also rejects missing, HTTP, localhost, `127.0.0.1`, and `10.0.2.2` API URLs.

Build one universal APK from the repository root after replacing the URL placeholder with the deployed Render HTTPS origin:

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://<service>.onrender.com
```

The artifact is `build/app/outputs/flutter-apk/app-release.apk`. If `android/key.properties` is absent, the build retains the existing debug-signing fallback so the demo APK remains installable. To create a privately release-signed APK, run the following from the repository root and answer `keytool`'s prompts locally:

```powershell
keytool -genkeypair -v -keystore android/gradport-upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias <private-alias>
Copy-Item android/key.properties.example android/key.properties
```

Fill in the four ignored `android/key.properties` values, rebuild, and securely back up the keystore and credentials. Keystores, properties, aliases, and passwords must never be committed. The current `com.example.proport_app` application ID is acceptable only for direct demo sideloading and must be replaced with the final owned identifier before Play Store release; `version: 2.0.0+1` supplies the current version name/code.

## Deferred work

Scanned-PDF raster OCR, PDF/DOCX generation, final Play Store/App Store identifiers and signing, production monitoring, and paid-instance capacity planning remain deferred. Local/R2 storage and console/SMTP/Brevo email share the existing abstractions, so those later tasks do not require API or Flutter-flow redesign.
