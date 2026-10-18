import { type PDFDocument, PDFName, PDFSignature } from 'pdf-lib';
import { AppError } from '../../common/errors/app-error.js';

const unsupported = () => new AppError(422, 'PORTFOLIO_ARTIFACT_UNSUPPORTED',
  'A PDF contains unsupported form fields or annotations. Open it in a PDF reader, print to PDF with visible annotations, and upload that copy. The original is unchanged.');

/** Only mutates the in-memory export copy. Never rewrites stored evidence. */
export function flattenExportForm(source: PDFDocument): void {
  try {
    // getForm() itself discards XFA in pdf-lib. Inspect the catalog first so
    // unsupported dynamic forms fail instead of silently losing their content.
    if (source.catalog.AcroForm()?.has(PDFName.of('XFA'))) throw unsupported();
    const form = source.getForm();
    const fields = form.getFields();
    // Do not imply that a digital signature survives flattening/recomposition.
    if (fields.some((field) => field instanceof PDFSignature)) throw unsupported();
    if (fields.length) {
      // Regenerate supported form values before flattening; stale appearances
      // must not replace current answers. Unsupported glyphs fail explicitly.
      for (const field of fields) form.markFieldAsDirty(field.ref);
      form.updateFieldAppearances();
      form.flatten({ updateFieldAppearances: false });
    }
  } catch {
    throw unsupported();
  }
}
