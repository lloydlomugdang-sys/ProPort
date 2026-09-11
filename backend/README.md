# GradPort Backend

This directory contains GradPort's Fastify and MongoDB backend. It includes the persistence foundation and the versioned authentication, current-user, portfolio, and document APIs used by the Flutter Android and iOS clients.

Authenticated PDF/JPEG/PNG uploads use private local object storage in development. Local OCR and embedded PDF text extraction are available for uploaded documents; document generation, cloud object storage, and deployment remain later work.

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
POST /api/v1/auth/refresh
POST /api/v1/auth/logout
```

Authenticated profile access is exposed under `/api/v1/users`:

```text
GET /api/v1/users/me
PATCH /api/v1/users/me
```

Both routes require a valid access token backed by its active server-side session. The PATCH route accepts only `firstName`, `lastName`, `program`, `yearLevel`, and `school`; email changes and client-selected user IDs are not accepted.

Authenticated document access is exposed under `/api/v1/documents`:

```text
GET    /api/v1/documents/categories
GET    /api/v1/documents
POST   /api/v1/documents
GET    /api/v1/documents/:documentId
GET    /api/v1/documents/:documentId/content
GET    /api/v1/documents/:documentId/ocr
POST   /api/v1/documents/:documentId/ocr
PATCH  /api/v1/documents/:documentId/ocr
DELETE /api/v1/documents/:documentId
```

Upload uses `multipart/form-data` with one `file` part plus `categoryKey`, `folderKey`, `title`, and `documentDate` (`YYYY-MM-DD`). `description` and `reflection` are optional. Valid PDF, JPG/JPEG, and PNG files are limited to 15 MB. Extension, declared MIME type, and file signature must agree. The user ID is always derived from the authenticated access token; client-supplied ownership fields are rejected.

Access tokens are HS256 JWTs valid for 15 minutes. Opaque refresh tokens are valid for 30 days, are stored only as SHA-256 hashes, rotate on every refresh, and revoke their token family when a replaced token is replayed. Passwords use Argon2id. Verification/reset codes contain six digits, expire after ten minutes, and are stored only as keyed hashes.

## MongoDB storage boundary

MongoDB stores account records, session/code records, category and report definitions, college-report answers, and document metadata. A document record contains an owner, category/folder, file name, MIME type, file kind, extension, size, checksum, and private `objectKey` reference. After extraction, its nested `ocr` record stores the processing status, immutable extracted `rawText`, user-editable `reviewedText`, engine name, and timestamps.

MongoDB must never contain uploaded file bytes, `Buffer` payloads, Base64 data, data URLs, GridFS identifiers, GridFS buckets, or file chunks. The repository and schema layers reject these values. Actual files are stored beneath the configured `LOCAL_STORAGE_PATH` by the development `ObjectStorage` adapter; generated object keys, not filesystem paths, are stored in MongoDB or exposed internally. The content endpoint and `DocumentService.openContent()` remain the file-read boundary. A cloud adapter can replace local storage without changing the document or OCR APIs.

## Document text extraction

Image OCR runs locally with Tesseract.js and the English trained-data npm package. Language data is installed with backend dependencies and is read locally; the API does not download OCR models at request time. JPEG and PNG dimensions are validated before OCR, with a 25-megapixel limit, and extraction has a 45-second backend timeout.

PDF.js extracts embedded text from PDFs without rendering pages. PDFs are limited to 100 pages and OCR text is limited to 200,000 characters. Password-protected PDFs are rejected. Image-only/scanned PDFs return `SCANNED_PDF_OCR_NOT_SUPPORTED`; rasterizing them is intentionally deferred to avoid system-executable and native rendering dependencies.

OCR starts synchronously with `POST /api/v1/documents/:documentId/ocr`. An atomic, expiring processing lease prevents duplicate concurrent work for the same document. `GET` reloads the persisted result and `PATCH` accepts only `reviewedText`; clients cannot replace `rawText` or ownership/security fields. Every operation derives ownership from the access token and returns the same safe document-not-found response for another user's ID. File contents and extracted text are never written to application logs.

Existing document records require no data migration: a missing `ocr` field is returned as `not_processed`, and OCR adds no index. Existing runtime `find`/`update` permissions on `documents` are sufficient.

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

## Deferred work

Private R2 storage, scanned-PDF raster OCR, PDF/DOCX generation, cloud deployment, production SMTP credential provisioning, and production database provisioning remain deferred. Document upload and OCR read through `ObjectStorage`; replacing the local adapter with R2 does not require a document API redesign. The console and SMTP implementations share the existing `EmailSender` interface, so changing providers later does not require an authentication API redesign.
