# Mixed PDF processing (Phase A)

The existing compiled analyze/split/cancel endpoints remain owner-scoped. Analysis
now returns `pages` (original page number, raw text, source, status) and `detection`
(`single`, `multiple`, `needs_review`). Gemini receives normalized text only;
Tesseract remains the image OCR engine. Raw/reviewed text and student reflections
are not rewritten by Gemini.

Add File analyzes a PDF once and reuses that session in the review screen.
Confident multi-document results open review automatically unless the user has
already edited the form. Single-document PDFs keep the normal metadata form;
single-page PDFs reuse the established metadata recommender on extracted text
instead of making a second segmentation/metadata request. Manual Separate remains
available, and failed-page retry preserves all reviewed fields and ranges.

## Limits and review

- One PDF, at most 15 MiB and 100 pages.
- Digital text is accepted with at least 40 Unicode letters/digits and six words
  of at least two letters/digits; sparse layers receive OCR fallback.
- At most ten fallback pages, processed sequentially, within the existing
  45-second PDF processing budget. Image recognition also uses the remaining
  budget. No persistent worker pool was introduced.
- Rasterization is at most 2x PDF scale and 2,000 pixels on the longest edge.
- Total extracted text remains capped at 200,000 characters.
- Blank pages are retained. Unreadable pages are explicit and prevent splitting.
- Review must cover all physical pages exactly once. Region splitting is not
  supported. Repeated CV headings remain within a single CV.
- A failed AI request falls back to deterministic proposals. Unknown content
  requires manual taxonomy review; no arbitrary Creative Title fallback is used.

## Deployment / indexes (not applied automatically)

Migration 003 registers the unique session ID and owner/expiry indexes on
`compiled_document_sessions`. It removes only the application's legacy
`expiresAt_1` TTL index, if it has the exact known TTL definition. The runtime
does not create indexes. Migrations 001/002 retain their existing checksums.

Run migration status and review the target before separately approving migration
execution. No migration against development/production Atlas is part of this
implementation. The maintenance role needs index creation/listing and removal of
that specific legacy index on this collection. Runtime needs only normal CRUD
on the compiled-session collection, not index-management privileges.

## Retries and cleanup

Split requests atomically claim a session. Successful receipts are persisted and
bound to owner, session, idempotency key, and normalized reviewed payload. The UI
retains its key and submitted payload after a lost response. Another service
instance cannot concurrently claim the same source. Completed receipts remain
available until the one-hour session expiry.
If the completion receipt acknowledgement is lost, saved documents are retained;
retry the same request. An unconfirmed database write must never trigger deletion
of documents that a committed receipt could subsequently return.

Analysis records cleanup intent before object upload. Cancellation and expired
session access delete the source before removing its database record. Each new
analysis also attempts cleanup of at most ten expired sessions for that owner.
Failures retain cleanup intent and do not claim successful deletion. Expiration
is checked in application code, not delegated to MongoDB TTL timing.

There is intentionally no ad-hoc background worker. Accounts that never return,
prolonged storage outages, and process termination during a split still need a
separately approved, durable reconciliation/garbage-collection job. A split left
in `processing` or `failed` is not automatically reclaimed, to avoid duplicate
documents or deletion of active work. Operators must reconcile such sessions
before retrying; do not reset/drop a real database to recover them.

## Acceptance still required

Test digital/scanned certificate + multi-page CV + certificate PDFs on Android
and iOS. Confirm automatic review only for confident multi-document results,
manual correction, stable retry after connectivity loss, explicit unreadable
pages, cancellation, saved documents after restart, and existing single-image /
single-PDF workflows. Check native rendering on the deployed Node platform;
PDF.js uses its existing optional native canvas package. No new dependency was
added. This phase does not change portfolio formatting or College Report.
