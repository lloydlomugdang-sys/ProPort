import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/screens/portfolio/models/portfolio_models.dart';
import 'package:proport_app/services/portfolio_export_service.dart';
import 'package:xml/xml.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('safe bounded filename cannot escape the export directory', () {
    expect(
      portfolioFileName('../ A/B \\ C: <student>?*', ExportFormat.pdf),
      'GradPort_A_B_C_student_Portfolio.pdf',
    );
    expect(
      portfolioFileName('.../\\', ExportFormat.docx),
      'GradPort_Student_Portfolio.docx',
    );
    expect(
      portfolioFileName('A' * 500, ExportFormat.pdf).length,
      lessThan(100),
    );
  });

  test('DOCX is a valid OOXML ZIP with equivalent safe public information', () {
    final bytes = PortfolioFileRenderer.docx(_content());
    expect(bytes.length, greaterThan(1000));
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    expect(
      archive.files.map((file) => file.name),
      unorderedEquals([
        '[Content_Types].xml',
        '_rels/.rels',
        'word/document.xml',
      ]),
    );
    for (final file in archive.files) {
      expect(
        () => XmlDocument.parse(utf8.decode(file.content)),
        returnsNormally,
      );
    }
    final body = XmlDocument.parse(
      utf8.decode(archive.findFile('word/document.xml')!.content),
    );
    final text = body
        .findAllElements('w:t')
        .map((node) => node.innerText)
        .join('\n');
    for (final expected in _expectedText) {
      expect(text, contains(expected));
    }
    expect(text, contains('A < B & C')); // XML escaping, not executable markup.
    expect(text, contains('No stored documents in this section.'));
    expect(body.findAllElements('w:pageBreakBefore').length, 7);
    expect(body.findAllElements('w:pgSz').single.getAttribute('w:w'), '11906');
    expect(text, isNot(contains('accessToken')));
    expect(text, isNot(contains('ownerId')));
    expect(text, isNot(contains('document-id')));
  });

  test(
    'PDF contains title-page and document text with embedded Unicode fonts',
    () async {
      final bytes = await _pdf(_content());
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      expect(bytes.length, greaterThan(1000));
      final text = _pdfText(bytes);
      for (final expected in _expectedText) {
        expect(text, contains(expected));
      }
      final raw = latin1.decode(bytes);
      expect(raw, contains('/FontFile2'));
      expect(raw.trimRight(), endsWith('%%EOF'));
      expect(text, isNot(contains('accessToken')));
      expect(text, isNot(contains('document-id')));
    },
  );

  test(
    'PDF paginates long metadata instead of dropping it or overflowing',
    () async {
      final bytes = await _pdf(
        _content(
          reflection: '${'A long reflection. ' * 1200}END OF REFLECTION',
        ),
      );
      expect(_pdfText(bytes), contains('END OF REFLECTION'));
      expect(
        RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)).length,
        greaterThan(8),
      );
    },
  );

  test(
    'partial list is explicitly disclosed rather than presented as complete',
    () {
      final content = _content(total: 150);
      expect(content.coverageNote, contains('1 of 150'));
      final archive = ZipDecoder().decodeBytes(
        PortfolioFileRenderer.docx(content),
      );
      expect(
        utf8.decode(archive.findFile('word/document.xml')!.content),
        contains('this export is incomplete'),
      );
    },
  );

  test(
    'actual PDF and DOCX files are written into unique temporary directories',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'gradport_export_test_',
      );
      addTearDown(() async {
        // Only our freshly allocated, verified disposable test directory.
        expect(
          await root.parent.resolveSymbolicLinks(),
          await Directory.systemTemp.resolveSymbolicLinks(),
        );
        expect(
          root.uri.pathSegments.where(
            (part) => part.startsWith('gradport_export_test_'),
          ),
          isNotEmpty,
        );
        await root.delete(recursive: true);
      });
      final store = PortfolioExportStore(temporaryDirectory: () async => root);
      final exporter = DevicePortfolioExporter(store: store);
      for (final format in ExportFormat.values) {
        final bytes = format == ExportFormat.pdf
            ? await _pdf(_content())
            : PortfolioFileRenderer.docx(_content());
        final name = portfolioFileName('Test Student', format);
        final file = await store.write(bytes, name, format);
        expect(await File(file.path).readAsBytes(), bytes);
        expect(file.sizeBytes, bytes.length);
        expect(file.name, name);
        final again = await store.write(bytes, name, format);
        expect(again.path, isNot(file.path));
        expect(file.path, startsWith(root.path));
        // Exercise real compute-isolate generation, bundled fonts and disk I/O.
        final generated = await exporter.generate(_content(), format);
        expect(await File(generated.path).length(), greaterThan(1000));
        if (format == ExportFormat.pdf) {
          expect(
            _pdfText(await File(generated.path).readAsBytes()),
            contains('Test José Student'),
          );
        } else {
          expect(
            ZipDecoder()
                .decodeBytes(await File(generated.path).readAsBytes())
                .findFile('word/document.xml'),
            isNotNull,
          );
        }
      }
      await expectLater(
        store.write(
          Uint8List.fromList([1]),
          '../outside.pdf',
          ExportFormat.pdf,
        ),
        throwsA(isA<PortfolioExportException>()),
      );
      await expectLater(
        store.write(
          Uint8List(0),
          'GradPort_Student_Portfolio.pdf',
          ExportFormat.pdf,
        ),
        throwsA(isA<PortfolioExportException>()),
      );
    },
  );

  // Opt-in synthetic fixtures for external PDF/Word compatibility inspection.
  const fixturePath = String.fromEnvironment('EXPORT_FIXTURE_DIR');
  if (fixturePath.isNotEmpty) {
    test('write synthetic export QA fixtures', () async {
      final directory = await Directory(fixturePath).create(recursive: true);
      await File(
        '${directory.path}/portfolio.pdf',
      ).writeAsBytes(await _pdf(_content()));
      await File(
        '${directory.path}/portfolio.docx',
      ).writeAsBytes(PortfolioFileRenderer.docx(_content()));
    });
  }
}

const _expectedText = [
  'ACADEMIC PORTFOLIO',
  'Test José Student',
  '3BSIT-2',
  'Monday 8:00 AM - 10:00 AM',
  'Professor Example',
  'Mobile Development',
  'IT 301',
  'First Semester 2026-2027',
  'Creative Title',
  'Curriculum Vitae',
  'Scholastic Record',
  'Certificates',
  'Accomplishments',
  'Other Achievements',
  'College Report',
  'Stored Training',
  '2026-09-14',
  'Training / Seminar',
  'A saved description',
  'My own reflection',
];

PortfolioExportContent _content({int total = 1, String? reflection}) =>
    PortfolioExportContent(
      titleFields: const {
        'Full Name': 'Test José Student',
        'Year & Section': '3BSIT-2',
        'Schedule': 'Monday 8:00 AM - 10:00 AM',
        "Instructor's Name": 'Professor Example',
        'Course': 'Mobile Development',
        'Course Code': 'IT 301',
        'Semester & Academic Year': 'First Semester 2026-2027',
      },
      totalDocuments: total,
      sections: [
        for (final name in [
          'Creative Title',
          ...PortfolioSummary.categorySections.values,
        ])
          PortfolioExportSection(
            name,
            name == 'Certificates'
                ? [
                    {
                      'Title': 'Stored Training',
                      'Date': '2026-09-14',
                      'Category': 'Certificates',
                      'Folder': 'Training / Seminar',
                      'File': 'certificate.pdf',
                      'Description': 'A saved description\nA < B & C',
                      'Reflection': reflection ?? 'My own reflection',
                    },
                  ]
                : [],
          ),
      ],
    );

Future<Uint8List> _pdf(PortfolioExportContent content) async =>
    PortfolioFileRenderer.pdf(
      content,
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );

/// Test-only reader of the writer's unencrypted text streams and Unicode CMaps.
/// This is not an uploaded-PDF parser and is never shipped in the application.
String _pdfText(Uint8List bytes) {
  final raw = latin1.decode(bytes);
  final objects = <int, String>{
    for (final match in RegExp(
      r'(\d+) 0 obj(.*?)endobj',
      dotAll: true,
    ).allMatches(raw))
      int.parse(match.group(1)!): match.group(2)!,
  };
  final streams = <int, String>{};
  for (final object in objects.entries) {
    final match = RegExp(
      r'stream\r?\n(.*?)\r?\nendstream',
      dotAll: true,
    ).firstMatch(object.value);
    if (match == null || object.value.contains('/Length1')) continue;
    final content = latin1.encode(match.group(1)!);
    streams[object.key] = latin1.decode(
      object.value.contains('/FlateDecode') ? zlib.decode(content) : content,
    );
  }
  // Each embedded font has its own subset character numbering.
  final fonts = <String, Map<int, String>>{};
  for (final object in objects.values) {
    final reference = RegExp(r'/ToUnicode\s+(\d+) 0 R').firstMatch(object);
    final name = RegExp(r'/Name/(F\d+)').firstMatch(object);
    if (reference == null || name == null) continue;
    final stream = streams[int.parse(reference.group(1)!)]!;
    final characters = stream
        .split('beginbfchar')
        .last
        .split('endbfchar')
        .first;
    fonts[name.group(1)!] = {
      for (final match in RegExp(
        r'<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>',
      ).allMatches(characters))
        int.parse(match.group(1)!, radix: 16): String.fromCharCode(
          int.parse(match.group(2)!, radix: 16),
        ),
    };
  }
  final output = StringBuffer();
  for (final stream in streams.values.where((s) => s.contains('BT'))) {
    for (final run in RegExp(r'BT(.*?)ET', dotAll: true).allMatches(stream)) {
      final font = RegExp(r'/(F\d+)\s+').firstMatch(run.group(1)!);
      if (font == null) continue;
      final glyphs = fonts[font.group(1)]!;
      for (final match in RegExp(
        r'<([0-9a-fA-F]+)>',
      ).allMatches(run.group(1)!)) {
        final hex = match.group(1)!;
        for (var i = 0; i + 4 <= hex.length; i += 4) {
          output.write(
            glyphs[int.parse(hex.substring(i, i + 4), radix: 16)] ?? '',
          );
        }
      }
      output.write(' ');
    }
  }
  return output.toString();
}
