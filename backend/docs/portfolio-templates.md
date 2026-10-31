# SO3: configurable supported portfolio structure

The single structural source of truth is
`src/config/portfolio-templates.json`. It is trusted, operator-managed data,
not a document-design language. PDF, DOCX, their TOCs, and Flutter's
summary/logical preview consume its effective active template. Uploaded file
classification and the folder taxonomy remain independent and unchanged.

## Supported schema and activation

The catalog contains `templates`. Each version has exactly:

- `id`: stable lowercase identifier; `name`: plain display text.
- `version`: positive integer, unique with `id`.
- `status`: `active` or `inactive`.
- `includeTableOfContents`: boolean.
- `sections`: all six existing category keys, each once, with `key`, plain-text
  `label`, unique nonnegative integer `order`, and boolean `enabled`, `required`,
  `generateCreativeTitle`.

Exactly one template is active for the single institutional scope. Every version
is validated, including inactive ones. Missing/unknown/duplicate section keys,
duplicate order/version, malformed booleans, extra properties, markup/control
characters, and ambiguous activation fail configuration loading. A validated,
sorted, frozen snapshot is resolved once at process startup, not repeatedly from
MongoDB during export. TypeScript's JSON import includes the catalog in compiled
output. A configuration change requires a normal backend build/restart; it does
not require changing either generator, a database migration, or an app rebuild.

There is no admin role or authorized settings UI in this repository. Therefore
there is **no template mutation endpoint** and no student template selection.
Only operators with repository/deployment configuration access manage this file.
Authenticated `GET /api/v1/portfolios/template` returns the safe effective
configuration in the usual `{data:{template},meta:{requestId}}` envelope. Flutter
loads it on entering summary/preview, coalesces concurrent reads, and clears its
cache on account change. Load failures show retry, never guessed local defaults.
Exports always use the backend's current effective template; a preview/file
already open is a snapshot and must be reopened after an operator activates a
different backend version.

## Example supported change (later test-backend QA, not production)

1. Copy version 1 as version 2 with the same `id`; mark version 1 `inactive` and
   version 2 `active`. Preserve all six section entries.
2. Give version 2 this `order`/`enabled` configuration:

   | Key | Order | Enabled |
   | --- | ---: | --- |
   | curriculum-vitae | 10 | true |
   | certificates | 20 | true |
   | accomplishments | 30 | true |
   | scholastic-record | 40 | true |
   | other-achievements | 50 | false |
   | college-report | 60 | true |

3. Keep or edit supported labels/booleans. Run typecheck, lint, and the portfolio
   tests before restarting the **test** backend. Do not edit the generator files.
4. Reopen the summary/preview in the Android test app and generate both formats.
   Confirm the new order, TOC targets, one applicable Creative Title per section,
   original evidence page order and saved College Report responses. Inspect the
   same files in a PDF reader and Microsoft Word. This physical QA is pending.

The shipped version 1 reproduces the existing category order and labels, enables
all sections and TOC, and retains applicable Creative Titles. `required` defaults
to false: no authoritative new mandatory-answer/section policy is invented.
Required flags are exposed to validation/planning and clients as advisory
metadata, **not** new missing-section export blockers. Existing title-page,
evidence, form-PDF and ownership validation still applies.

## Inclusion and Creative Titles

- Disabled sections contribute no pages, title, TOC entry, storage reads or
  College Report rendering. Stored artifacts/responses are never changed.
- Enabled sections follow template order. Folder/date/creation/id ordering and
  ordered attachment pages within a section remain deterministic.
- Optional `creativeTitles` maps on the existing owned portfolio record hold
  student-authored plain text (supported section keys, at most 200 characters).
  Summary's **Edit Section Creative Titles** action saves through existing
  owner-scoped PATCH; reopening/prefilling/exporting preserves it. Blank text
  clears a saved title. Disabling a section or title rule retains that text.
- `generateCreativeTitle:true` uses that saved text once before the section's
  evidence, even with multiple files. No upload is required. No text is invented
  when none is saved. Old single-page Creative Title uploads still serve as the
  cover when there is no saved text. Multiple legacy covers, a multipage cover,
  or both a saved title and legacy cover fail actionably rather than discard any.
- `generateCreativeTitle:false` deliberately excludes both the optional text
  cover and legacy creative-title artifact from this export only.
- PDF TOC numbers are measured from the actual filtered page plan; DOCX uses
  editable section hyperlinks/bookmarks, not invented Word page numbers. TOC can
  be omitted cleanly. Empty sections add no generic metadata/cover pages.

Legacy portfolios without `creativeTitles` or a template association use the
current effective template. This is not a historical template snapshot system.
The additive optional map needs no index change, migration or production seed.
The College Report's separate 10-section/62-item questionnaire template is not
repurposed as a portfolio template and its source wording remains unchanged.

## Safety, performance and limits

Both generators share `planPortfolioSections`; rendering-specific code remains
separate. No owner ID, template ID, HTML, CSS or executable structure is accepted
from students. Evidence reads/rendering stay sequential and bounded. Existing
font caching, no-form PDF reserialization avoidance, direct raster PNG reuse,
PNG ZIP storage, source limits and explicit unsupported/corrupt failures remain.
Disabling College Report also avoids its database read. No export timeouts were
increased and no dependencies were added.

Global PDF sizing/margins/body typography: **DEFERRED UNTIL INTERVIEW**, unchanged.
Unsupported: arbitrary page layouts, complex unimplemented formatting, new
artifact types/sections, font/margin editors, drag-and-drop design, user HTML/CSS,
scripting, AI interpretation of future dean instructions, student activation,
per-college active scopes and historical template pinning. Such changes need
separate approval and implementation; SO3 covers the supported structure only.
