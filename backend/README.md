# GradPort Backend — Phase 1

This directory is the isolated backend foundation for GradPort. Phase 1 provides Fastify startup, strict environment validation, request logging, health/readiness endpoints, local service adapters, Mongoose schemas, and seed definitions. It does not modify or integrate with the Flutter application.

## Requirements

- Node.js 22.15 or newer (below Node 25)
- npm 10 or newer

Docker is not required. The default configuration uses a non-persistent mock database, local object storage, and a console-only email adapter. No message is delivered over the network.

## Local setup without Docker

```powershell
cd backend
npm install
Copy-Item .env.example .env
npm run dev
```

The server defaults to `http://127.0.0.1:3000`.

```text
GET /health
GET /ready
```

`/ready` deliberately reports `mock`, `local`, and `console` so local adapters cannot be confused with production services. Runtime files are stored beneath `.local-data/`, which is ignored by Git.

Environment files are not loaded automatically in Phase 1. Set variables in the shell when overriding defaults, or run with the defaults shown in `.env.example`.

## Optional native MongoDB connection

No MongoDB server is required for Phase 1. If a local server becomes available, configure it explicitly:

```powershell
$env:DATABASE_DRIVER='mongodb'
$env:MONGODB_URI='mongodb://127.0.0.1:27017'
$env:MONGODB_DB_NAME='gradport'
npm run dev
```

The API will still start if the initial connection fails so `/health` remains available, but `/ready` returns `503` until MongoDB is reachable.

## Seeds

Seeds are idempotent, insert-only definitions for the current document categories/folders and the versioned college-engagement report template. They never run during application startup and refuse to run with the mock driver.

```powershell
$env:DATABASE_DRIVER='mongodb'
$env:MONGODB_URI='mongodb://127.0.0.1:27017'
npm run seed
```

Do not run the seed command unless the target MongoDB database has been deliberately selected and approved.

## Verification

```powershell
npm run typecheck
npm run lint
npm test
npm run build
```

## Deferred architecture

Authentication, document routes, Flutter integration, real email, private R2 storage, portfolio generation, managed-cloud deployment, and traditional non-ML OCR remain outside Phase 1. The future deployment target remains Node.js 24 LTS on Render Singapore with MongoDB Atlas, private Cloudflare R2, and Resend, subject to later approval gates.
