# Phase B: official portfolio PDF layout

Reference: `Portfolio_Format_2026 (1).pdf`, supplied by the project owner.
Phase A baseline: `918f62700b1458ecda00336c215fa1de849c4262` on
`feature/mixed-pdf-portfolio`. No migrations, environment/configuration,
dependencies, OCR, authentication or storage permissions are changed.

## Content and ordering

Production PDF order:

1. Standard Title: the existing seven user-entered title fields only.
2. Creative Title: actual supplied creative-title documents, once only.
3. Table of Contents: actual major sections, present subtopics and documents.
4. Curriculum Vitae.
5. Unofficial TOR - Bachelor's Degree with Reflection (`scholastic-record`).
6. Certificates: Seminars (Onsite), Other Seminars, Trainings.
7. Accomplishments: Thesis/Capstone, Case Studies, Projects, Assessments.
8. Other Achievements.
9. College Report: existing uploaded evidence only.

Category/folder order reuses `CATEGORY_SEEDS.sortOrder`. `cv` remains a legacy
alias for `curriculum-vitae`. Documents sort by document date, creation time, ID.
Legacy folders under recognized categories stay there, after known folders,
ordered by key. Unknown categories fail explicitly with
`PORTFOLIO_CATEGORY_UNSUPPORTED`; originals remain untouched for manual
categorization. They are never omitted or assigned to Creative Title.

Only actual descriptions, outlines within uploaded documents and student
reflections are included. No invented PO/PEO reflection, abridged project chapter,
institution, seal, signature, student identifier or questionnaire answers.
The schema has ordered generic attachments, **not identified project screenshot
records**. Embedded screenshots remain intact. Two screenshots per page / maximum
ten pages per project therefore remains a manual requirement: no guessing,
extraction, reconstruction or silent removal. Phase C questionnaire work is not
implemented.

## Layout and font compliance

Generated pages are US Letter, 612 x 792 points. Margins: left 108;
top/right/bottom 72. Normal generated text uses 12-point fonts and 24-point
baselines. Footers stay inside the margins. Wrapping measures the selected font
and handles long words, paragraph boundaries and long titles. Long descriptions
and reflections paginate in full; short captions share the image page. Nonempty
major sections start on explicit dividers; absent sections add no blank pages.

`portfolio-layout.ts` centralizes geometry, wrapping, fitting and fonts.
`PortfolioGeneratorService` accepts a `PortfolioFontLoader` as its optional third
constructor argument. An approved loader can register fontkit and embed licensed
regular/bold bytes into the supplied PDFDocument without rewriting layout or
generation. Wire it at service construction once approved assets are supplied.
There are no client-controlled font paths.

**Arial compliance is blocked:** the repository has licensed Noto Sans Flutter
assets but no approved Arial asset or server fontkit loader. The server retains
its built-in Helvetica/Helvetica-Bold fallback, explicitly **not Arial**. No
proprietary fonts were copied/downloaded and no dependencies were added.
Unsupported characters produce `PORTFOLIO_FONT_UNSUPPORTED`, never silent text
substitution. Supply approved Arial regular/bold assets and their license, then
validate embedding/character coverage before claiming exact font compliance.

**Exact institutional Standard Title compliance is pending:** the reference
points to a separate title example that was not supplied. The current clean page
retains the seven existing user fields without inventing the missing design.

## Artifacts and page numbers

Pass one plans wrapped text and embedded artifact pages; TOC entries reference
real page-plan indices. TOC rows wrap without truncation in a width that reserves
the page-number column. The measured TOC page count shifts only the following
main content. Pass two renders the exact plan, so changes in text or artifact
length update final page numbers.

PDF pages embed as vector content, uniformly scaled and centered in Letter
printable rectangles. Original visible CropBox/MediaBox intersections and page
rotation are respected, without extra cropping, stretching or revealing hidden
source margins. Landscape sources use **landscape Letter (792 x 612)** with the
same physical margins, avoiding narrow portrait compression. Source typography
is retained, not rewritten into 12-point text. Tiny text in unusually large source
pages still needs manual readability review. PDFs with form widgets or non-link
annotations fail explicitly with `PORTFOLIO_ARTIFACT_UNSUPPORTED`, requesting a
flattened copy rather than silently losing answers/stamps/ink. Originals stay
unchanged. Link text remains visible, but interactive links are not rebuilt.

Images use portrait Letter pages, centered and proportionally fitted below
measured captions and above footers. No artificial upscaling. Multi-attachment
page order and indicators remain intact.

## Retrieval and safety

Only portfolio export uses `listPortfolioBatchForOwner`: 100-document `_id`
keyset batches, always filtered by authenticated owner. The normal document API
keeps its 100-item cap. Export has an explicit 500-document ceiling, not silent
truncation. Existing 50 MiB total source, 15 MiB per artifact and 150-page limits
remain; streamed bytes are checked as well as stored estimates. Limit failures
remain `413 PORTFOLIO_TOO_LARGE` with actionable messages. Source records/files
remain untouched. Authentication, ownership and storage access are unchanged.
No indexes or migrations are required.

## Flutter and manual acceptance

Preview order: user title -> actual Creative Title -> Sections Included content
indicator -> official main sections. Server-sorted folders and date/creation/ID
tie-breakers match the PDF. This is a logical preview, not a PDF viewer. Partial
preview coverage is disclosed; the server PDF is not capped at 100 documents.
Save to Device, Share, persistence and reopening remain unchanged.

DOCX remains the existing editable metadata outline, not artifact-complete or
certified official-format output. Its shared ordering change does not redesign
its file format or pretend to embed uploaded documents.

Automated coverage includes order, font injection, Letter/margins, double spacing,
wrapped TOC targets, complete reflections, portrait/landscape/rotated PDF fitting,
real image placement, absent sections, unknown categories, limits, 110-document
owner-scoped traversal and Flutter preview/export order. Database tests use only
the existing guarded local disposable databases. Never source Atlas environment
files for these tests.

Physical/manual checklist:

- Export CV, TOR/reflection, certificate/training, accomplishment and College
  Report evidence; check front matter, main-section order and every TOC target.
- Open the PDF on Android and desktop. Print Letter at actual size; measure the
  asymmetric margins and review all landscape pages for readability.
- Check long reflections, multiple creative titles, scanned multi-attachments
  and source edge content. Use static PDFs for interactive/form evidence.
- Save, Share, cancel dialogs, restart/login and reopen My Portfolios.
- With more than 100 documents, confirm a complete server PDF or actionable
  limit error; partial preview/DOCX coverage must not imply complete PDF output.
- Obtain the missing institutional title reference and licensed Arial assets.
  Manually check project screenshot rules until structured authoring is approved.
- No deployment or Atlas migration is part of this phase.
