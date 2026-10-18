// Historical metadata-only renderer retained exclusively as a regression fixture.
// Never import this file into lib/. Real portfolio PDFs use the backend route.
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:proport_app/services/portfolio_export_service.dart';

class LegacyOutlinePdfFixture {
  static Future<Uint8List> pdf(
    PortfolioExportContent content,
    ByteData regular,
    ByteData bold,
  ) async {
    final document = pw.Document(
      title: 'GradPort Portfolio',
      creator: 'GradPort',
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(regular),
        bold: pw.Font.ttf(bold),
      ),
    );
    const margin = pw.EdgeInsets.all(50);
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: margin,
        build: (_) => [
          pw.SizedBox(height: 70),
          pw.Header(level: 0, text: 'ACADEMIC PORTFOLIO'),
          pw.SizedBox(height: 28),
          for (final field in content.titleFields.entries)
            ..._pdfField(field.key, field.value),
          pw.SizedBox(height: 24),
          pw.Paragraph(text: content.coverageNote),
          pw.Paragraph(
            text:
                'Document metadata is included. Original uploaded images and PDF pages are not embedded in this export.',
          ),
        ],
      ),
    );
    for (final section in content.sections) {
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: margin,
          maxPages: 1000,
          header: (_) => pw.Text(
            'GradPort | ${section.name}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          footer: (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Page ${context.pageNumber}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
          build: (_) => [
            pw.Header(level: 0, text: section.name),
            if (section.documents.isEmpty)
              pw.Paragraph(text: 'No stored documents in this section.'),
            for (final fields in section.documents) ...[
              for (final field in fields.entries)
                ..._pdfField(field.key, field.value),
              pw.Divider(),
              pw.SizedBox(height: 12),
            ],
          ],
        ),
      );
    }
    return document.save();
  }

  static List<pw.Widget> _pdfField(String label, String value) => [
    pw.Text(
      label,
      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
    ),
    // Small paragraph chunks can cross pages even for very long reflections.
    for (final part in _textChunks(value.isEmpty ? 'Not provided' : value))
      pw.Paragraph(
        text: part,
        style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
      ),
    pw.SizedBox(height: 6),
  ];

  static Iterable<String> _textChunks(String value) sync* {
    final text = _cleanText(value);
    // Bound a single layout node, including unbroken user text.
    final runes = text.runes.toList();
    var start = 0;
    while (start < runes.length) {
      var end = (start + 400).clamp(0, runes.length);
      // Prefer a whitespace boundary; never split a Unicode code point.
      if (end < runes.length) {
        for (var i = end - 1; i > start + 200; i--) {
          if (runes[i] == 32 || runes[i] == 10) {
            end = i + 1;
            break;
          }
        }
      }
      yield String.fromCharCodes(runes.sublist(start, end));
      start = end;
    }
  }

  static String _cleanText(String value) => value
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\uFFFE\uFFFF]'), '');
}
