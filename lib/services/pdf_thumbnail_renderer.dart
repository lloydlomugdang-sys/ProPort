import 'dart:typed_data';
import 'package:printing/printing.dart';

/// Contract for rasterizing page 1 of a PDF into a displayable PNG image.
abstract class PdfThumbnailRenderer {
  /// Renders page 1 (index 0) of [pdfBytes] at the specified [dpi].
  /// Returns raw PNG image bytes, or `null` if rasterization fails or is unsupported.
  Future<Uint8List?> renderPage1(Uint8List pdfBytes, {double dpi = 72.0});
}

/// Default production implementation using `package:printing`.
/// Relies exclusively on `Printing.raster` through the public package API.
class DefaultPdfThumbnailRenderer implements PdfThumbnailRenderer {
  const DefaultPdfThumbnailRenderer();

  @override
  Future<Uint8List?> renderPage1(Uint8List pdfBytes, {double dpi = 72.0}) async {
    try {
      await for (final raster in Printing.raster(
        pdfBytes,
        pages: const [0],
        dpi: dpi,
      )) {
        return await raster.toPng();
      }
    } catch (_) {
      // Gracefully fall back if rasterization fails or platform is unavailable.
    }
    return null;
  }
}

