// Historical metadata-only writer, retained solely for regression fixtures.
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:proport_app/services/portfolio_export_service.dart';

class PortfolioFileRenderer {
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
            _docxParagraph(
              body,
              'ACADEMIC PORTFOLIO — EDITABLE OUTLINE',
              bold: true,
            );
            for (final field in content.titleFields.entries) {
              _docxField(body, field);
            }
            _docxParagraph(body, content.coverageNote);
            _docxParagraph(
              body,
              'Historical metadata-only DOCX fixture. No evidence embedded.',
            );
            for (final section in content.sections) {
              if (section.documents.isEmpty) continue;
              if (section.name == 'Creative Title') {
                for (final document in section.documents) {
                  _docxParagraph(
                    body,
                    document['Title'] ?? '',
                    bold: true,
                    pageBreak: true,
                  );
                  for (final field in document.entries.where(
                    (field) => field.key != 'Title',
                  )) {
                    _docxField(body, field);
                  }
                }
                continue;
              }
              _docxParagraph(
                body,
                section.name,
                size: 24,
                bold: true,
                pageBreak: true,
              );
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
                  attributes: {'w:w': '12240', 'w:h': '15840'},
                );
                body.element(
                  'w:pgMar',
                  attributes: {
                    'w:top': '1440',
                    'w:right': '1440',
                    'w:bottom': '1440',
                    'w:left': '2160',
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
    int size = 24,
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
                'w:after': '0',
                'w:line': '480',
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
                  attributes: {'w:ascii': 'Noto Sans', 'w:hAnsi': 'Noto Sans'},
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
