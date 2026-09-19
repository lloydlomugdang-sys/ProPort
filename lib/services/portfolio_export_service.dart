import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:xml/xml.dart';

import '../screens/portfolio/models/portfolio_models.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'document_service.dart';

/// An explicit public-data projection: no tokens, storage keys or internal IDs.
class PortfolioExportContent {
  const PortfolioExportContent({
    required this.titleFields,
    required this.sections,
    required this.totalDocuments,
  });

  final Map<String, String> titleFields;
  final List<PortfolioExportSection> sections;
  final int totalDocuments;
  int get includedDocuments =>
      sections.fold(0, (sum, section) => sum + section.documents.length);

  String get coverageNote => includedDocuments < totalDocuments
      ? 'Includes $includedDocuments of $totalDocuments stored documents. '
            'The current document API returns at most 100 entries; this export is incomplete.'
      : 'Includes $includedDocuments stored documents.';

  static const attachmentNote =
      'Document metadata is included. Original uploaded images and PDF pages '
      'are not embedded in this export.';

  factory PortfolioExportContent.fromDocuments(
    PortfolioInfo info,
    DocumentService service,
  ) {
    if (service.isLoading ||
        !service.hasLoadedDocuments ||
        !service.hasLoadedCategories ||
        service.errorMessage != null) {
      throw const PortfolioExportException(
        'Documents are not ready. Please try exporting again.',
      );
    }
    final summary = PortfolioSummary.fromDocumentSummary(service.summary);
    final groups = <String, List<Map<String, String>>>{
      for (final section in summary.sections) section.name: [],
    };
    for (final document in service.documents) {
      final category = service.categories
          .where((value) => value.key == document.categoryKey)
          .firstOrNull;
      final folder = category?.folders
          .where((value) => value.key == document.folderKey)
          .firstOrNull;
      final section = PortfolioSummary.sectionFor(document);
      groups.putIfAbsent(section, () => []).add({
        'Title': document.title,
        'Date': document.documentDate.toIso8601String().substring(0, 10),
        'Category': category?.name ?? section,
        'Folder': folder?.name ?? document.folderKey,
        'File': document.originalFileName,
        if (document.description?.trim().isNotEmpty ?? false)
          'Description': document.description!,
        if (document.reflection?.trim().isNotEmpty ?? false)
          'Reflection': document.reflection!,
      });
    }
    return PortfolioExportContent(
      titleFields: {
        'Full Name': info.fullName,
        'Year & Section': info.yearAndSection,
        'Schedule': info.formattedSchedule,
        "Instructor's Name": info.instructorName,
        'Course': info.course,
        'Course Code': info.courseCode,
        'Semester & Academic Year': info.semesterAndYear,
      },
      sections: [
        for (final entry in groups.entries)
          PortfolioExportSection(entry.key, entry.value),
      ],
      totalDocuments: service.summary.totalCount,
    );
  }
}

class PortfolioExportSection {
  const PortfolioExportSection(this.name, this.documents);

  final String name;
  final List<Map<String, String>> documents;
}

class PortfolioExportException implements Exception {
  const PortfolioExportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PortfolioExportFile {
  const PortfolioExportFile({
    required this.path,
    required this.name,
    required this.format,
    required this.sizeBytes,
  });

  final String path;
  final String name;
  final ExportFormat format;
  final int sizeBytes;
  String get mimeType => format == ExportFormat.pdf
      ? 'application/pdf'
      : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
}

/// Injected through PortfolioScope for tests; it owns no account/document state.
abstract interface class PortfolioExporter {
  Future<PortfolioExportFile> generate(
    PortfolioExportContent content,
    ExportFormat format,
  );
  Future<void> share(PortfolioExportFile file, Rect origin);
}

class DevicePortfolioExporter implements PortfolioExporter {
  const DevicePortfolioExporter({this.store, this.authService});

  final PortfolioExportStore? store;
  final AuthService? authService;

  @override
  Future<PortfolioExportFile> generate(
    PortfolioExportContent content,
    ExportFormat format,
  ) async {
    final Uint8List bytes;
    if (format == ExportFormat.pdf) {
      if (authService == null) {
        throw const PortfolioExportException(
          'Unable to generate your complete portfolio. Check your connection and try again.',
        );
      }
      try {
        bytes = await authService!.authenticatedPostBytes(
          '/api/v1/portfolios/export/pdf',
          body: {
            'fullName': content.titleFields['Full Name'] ?? '',
            'yearAndSection': content.titleFields['Year & Section'] ?? '',
            'schedule': content.titleFields['Schedule'] ?? '',
            'instructorName': content.titleFields["Instructor's Name"] ?? '',
            'course': content.titleFields['Course'] ?? '',
            'courseCode': content.titleFields['Course Code'] ?? '',
            'semesterAndYear':
                content.titleFields['Semester & Academic Year'] ?? '',
          },
          requestTimeout: const Duration(seconds: 90),
        );
      } on ApiException catch (error) {
        if (error.statusCode == 0 ||
            error.code == 'NETWORK_ERROR' ||
            error.message.contains('reach the server') ||
            error.message.contains('connection')) {
          throw const PortfolioExportException(
            'Unable to generate your complete portfolio. Check your connection and try again.',
          );
        }
        throw PortfolioExportException(error.message);
      } catch (_) {
        throw const PortfolioExportException(
          'Unable to generate your complete portfolio. Check your connection and try again.',
        );
      }
    } else {
      // DOCX export: editable outline
      bytes = await compute(_renderDocxOnly, content);
    }
    return (store ?? PortfolioExportStore()).write(
      bytes,
      portfolioFileName(content.titleFields['Full Name'] ?? '', format),
      format,
    );
  }

  @override
  Future<void> share(PortfolioExportFile file, Rect origin) async {
    if (!await File(file.path).exists()) {
      throw const PortfolioExportException(
        'The temporary file is no longer available. Please export again.',
      );
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: file.mimeType)],
        subject: 'GradPort Portfolio',
        sharePositionOrigin: origin,
      ),
    );
    // A dismissed share sheet is not a failed generation or a claimed save.
  }
}

Uint8List _renderDocxOnly(PortfolioExportContent content) =>
    PortfolioFileRenderer.docx(content);

String portfolioFileName(String fullName, ExportFormat format) {
  var student = fullName
      .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (student.isEmpty) student = 'Student';
  if (student.length > 60) student = student.substring(0, 60);
  return 'GradPort_${student}_Portfolio.${format.name}';
}

/// Writes only to unique app-cache subdirectories; never shared external storage.
class PortfolioExportStore {
  PortfolioExportStore({Future<Directory> Function()? temporaryDirectory})
    : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final Future<Directory> Function() _temporaryDirectory;

  Future<PortfolioExportFile> write(
    Uint8List bytes,
    String name,
    ExportFormat format,
  ) async {
    if (bytes.isEmpty ||
        !RegExp(
          r'^GradPort_[A-Za-z0-9_-]+_Portfolio\.(pdf|docx)$',
        ).hasMatch(name)) {
      throw const PortfolioExportException('Unable to create the export file.');
    }
    final temporary = await _temporaryDirectory();
    final root = await Directory(
      '${temporary.path}/gradport_exports',
    ).create(recursive: true);
    final directory = await root.createTemp('export_');
    final file = File('${directory.path}/$name');
    try {
      await file.writeAsBytes(bytes, flush: true);
      if (await file.length() != bytes.length) {
        throw const PortfolioExportException(
          'Unable to finish writing the file.',
        );
      }
      return PortfolioExportFile(
        path: file.path,
        name: name,
        format: format,
        sizeBytes: bytes.length,
      );
    } catch (_) {
      // Only the exact file/directory created above is eligible for cleanup.
      if (await file.exists()) await file.delete();
      await directory.delete();
      rethrow;
    }
  }
}

class PortfolioFileRenderer {
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
          pw.Paragraph(text: PortfolioExportContent.attachmentNote),
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

  /// Minimal OOXML package: no macros, remote links, fields, templates or IDs.
  static Uint8List docx(PortfolioExportContent content) {
    final body = XmlBuilder();
    body.processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
    body.element(
      'w:document',
      attributes: {'xmlns:w': _wordNs},
      nest: () {
        body.element(
          'w:body',
          nest: () {
            _docxParagraph(body, 'ACADEMIC PORTFOLIO', size: 36, bold: true);
            for (final field in content.titleFields.entries) {
              _docxField(body, field);
            }
            _docxParagraph(body, content.coverageNote);
            _docxParagraph(body, PortfolioExportContent.attachmentNote);
            for (final section in content.sections) {
              _docxParagraph(
                body,
                section.name,
                size: 32,
                bold: true,
                pageBreak: true,
              );
              if (section.documents.isEmpty) {
                _docxParagraph(body, 'No stored documents in this section.');
              }
              for (final document in section.documents) {
                for (final field in document.entries) {
                  _docxField(body, field);
                }
                _docxParagraph(body, '');
              }
            }
            body.element(
              'w:sectPr',
              nest: () {
                body.element(
                  'w:pgSz',
                  attributes: {'w:w': '11906', 'w:h': '16838'},
                );
                body.element(
                  'w:pgMar',
                  attributes: {
                    'w:top': '1000',
                    'w:right': '1000',
                    'w:bottom': '1000',
                    'w:left': '1000',
                    'w:header': '500',
                    'w:footer': '500',
                    'w:gutter': '0',
                  },
                );
              },
            );
          },
        );
      },
    );
    final archive = Archive();
    for (final part in {
      '[Content_Types].xml': _contentTypes,
      '_rels/.rels': _relationships,
      'word/document.xml': body.buildDocument().toXmlString(),
    }.entries) {
      final bytes = utf8.encode(part.value);
      archive.addFile(ArchiveFile(part.key, bytes.length, bytes));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static void _docxField(XmlBuilder builder, MapEntry<String, String> field) {
    _docxParagraph(builder, field.key, bold: true);
    for (final part in _textChunks(
      field.value.isEmpty ? 'Not provided' : field.value,
    )) {
      _docxParagraph(builder, part);
    }
  }

  static void _docxParagraph(
    XmlBuilder builder,
    String text, {
    int size = 22,
    bool bold = false,
    bool pageBreak = false,
  }) {
    builder.element(
      'w:p',
      nest: () {
        builder.element(
          'w:pPr',
          nest: () {
            if (pageBreak) builder.element('w:pageBreakBefore');
            if (bold) builder.element('w:keepNext');
            builder.element(
              'w:spacing',
              attributes: {
                'w:after': '140',
                'w:line': '300',
                'w:lineRule': 'auto',
              },
            );
          },
        );
        builder.element(
          'w:r',
          nest: () {
            builder.element(
              'w:rPr',
              nest: () {
                builder.element(
                  'w:rFonts',
                  attributes: {'w:ascii': 'Calibri', 'w:hAnsi': 'Calibri'},
                );
                if (bold) builder.element('w:b');
                builder.element('w:sz', attributes: {'w:val': '$size'});
              },
            );
            final lines = _cleanText(text).split('\n');
            for (var i = 0; i < lines.length; i++) {
              if (i > 0) builder.element('w:br');
              builder.element(
                'w:t',
                attributes: {'xml:space': 'preserve'},
                nest: lines[i],
              );
            }
          },
        );
      },
    );
  }

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

  static const _wordNs =
      'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  static const _contentTypes =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';
  static const _relationships =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="document" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';
}

String portfolioExportError(Object error) {
  if (error is ApiException) {
    if (error.statusCode == 429 || error.code == 'RATE_LIMITED') {
      return 'Too many export attempts. Please wait a moment and try again.';
    }
    if (error.statusCode != null && error.statusCode! >= 500) {
      return 'The export server is temporarily unavailable. Please try again.';
    }
    if (error.code == 'NETWORK_ERROR') {
      return 'Unable to connect. Check your internet connection and try again.';
    }
    if (error.code == 'NETWORK_TIMEOUT') {
      return 'The export took too long to respond. Please try again.';
    }
    if (error.statusCode == 401) {
      return 'Your session has expired. Please log in again.';
    }
    return error.message.isNotEmpty
        ? error.message
        : 'Unable to export the portfolio. Please try again.';
  }
  if (error is PortfolioExportException) return error.message;
  return 'Unable to export the portfolio. Please try again.';
}
