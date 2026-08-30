# GradPort Backend — Phase 2A

This directory contains GradPort's isolated Fastify and MongoDB backend foundation. Phase 2A activates persistence, versioned indexes, idempotent reference-data seeds, and repositories without adding authentication or application routes.

Nothing in this phase integrates with Flutter, Android, uploads, OCR, document generation, cloud object storage, real email, or deployment.

## Requirements

- Node.js 22.15 or newer and below Node 25
- npm 10 or newer
- Internet access for npm installation and the first disposable MongoDB test-binary download

Docker is not required. Normal local development still defaults to a mock database, local storage, and console email.

```powershell
Set-Location backend
npm ci
npm run dev
```

The existing endpoints remain:

```text
GET /health
GET /ready
```

## MongoDB storage boundary

MongoDB stores account records, session/code records, category and report definitions, college-report answers, and document metadata. A document record contains an owner, category/folder, file name, MIME type, file kind, extension, size, checksum, and private `objectKey` reference.

MongoDB must never contain uploaded file bytes, `Buffer` payloads, Base64 data, data URLs, GridFS identifiers, GridFS buckets, file chunks, or embedded document content. The repository and schema layers reject these values. Actual files belong in private object storage during a later approved phase.

Normal repository results never contain `passwordHash`, `refreshTokenHash`, or `codeHash`, including create and update results. Purpose-specific credential access is deferred to the authentication phase.

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

Grant `find` only on:

- `document_categories`
- `report_templates`

Create user `gradport_dev_app` with only this role. Restrict it to `gradport-dev`.

### `gradportDevMaintainer` custom role

Inherit `gradportDevRuntime`, then add:

- `createCollection` and `listCollections` on `gradport_dev`
- `createIndex` and `listIndexes` on the seven application collections
- `find`, `insert`, `update`, and `remove` on `_gradport_migrations` and `_gradport_migration_lock`
- `find`, `insert`, and `update` on `document_categories` and `report_templates`

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

The files are loaded only by explicit Atlas/database npm commands. Never pass a URI on a command line, print it, or add it to tracked documentation.

## Migrations and seeds

Mongoose automatic index creation remains disabled. `001_initial_indexes` creates the 17 named indexes declared by the seven schemas and records its checksum in `_gradport_migrations`. An expiring lock prevents concurrent migration execution.

Migrations are forward-only. No rollback, index-drop, collection-drop, truncate, or database-reset command exists.

Seeds insert the six category definitions and `college-engagement-v1` using stable upsert keys and `$setOnInsert`. They never delete or overwrite data, require current migrations, and fail if stored seed content has drifted.

Every database command requires explicit confirmation:

```powershell
npm run db:ping -- --confirm-database=gradport_dev
npm run db:migrate -- --confirm-database=gradport_dev
npm run db:migrate:status -- --confirm-database=gradport_dev
npm run db:seed -- --confirm-database=gradport_dev
npm run db:verify -- --confirm-database=gradport_dev
```

`db:ping` uses runtime credentials. Migration, seed, status, and verification commands use the temporary maintenance credentials. Output is intentionally limited to the database name, statuses, counts, and elapsed time.

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

## Deferred work

Authentication routes and hash lookup, Flutter integration, document upload, private R2 storage, real email, OCR, PDF/DOCX generation, cloud deployment, and production database support remain outside Phase 2A.
