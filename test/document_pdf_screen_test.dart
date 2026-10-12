import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:proport_app/screens/files/document_ocr_screen.dart';
import 'package:proport_app/screens/files/document_pdf_screen.dart';
import 'package:proport_app/screens/files/view_files_screen.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/document_models.dart';
import 'package:proport_app/services/document_scope.dart';
import 'package:proport_app/services/document_service.dart';

final _pagePng = Uint8List.fromList(
  img.encodePng(img.Image(width: 200, height: 300)),
);

// Native rasterization/encoding is a platform boundary, not widget-test work.
// Supply deterministic page PNGs without awaiting dart:ui.toByteData in FakeAsync.
class _TestRaster extends PdfRaster {
  _TestRaster() : super(200, 300, Uint8List(0));
  @override
  Future<Uint8List> toPng() async => _pagePng;
}

class _RasterPlatform extends PrintingPlatform {
  int count = 2;
  bool fail = false;
  Uint8List? received;
  @override
  Future<PrintingInfo> info() async => const PrintingInfo(canRaster: true);
  @override
  Stream<PdfRaster> raster(
    Uint8List document,
    List<int>? pages,
    double dpi,
  ) async* {
    received = document;
    expect(
      pages,
      isNull,
      reason: 'The viewer must render all PDF pages, not attachment count.',
    );
    if (fail) throw StateError('private renderer detail');
    for (var index = 0; index < count; index++) {
      yield _TestRaster();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected printing operation');
}

class _Auth extends AuthService {
  Uint8List bytes = Uint8List.fromList([37, 80, 68, 70]);
  Object? error;
  Completer<Uint8List>? pending;
  final paths = <String>[];
  @override
  Future<Uint8List> authenticatedGetBytes(
    String path, {
    Duration? requestTimeout,
  }) async {
    paths.add(path);
    if (error != null) throw error!;
    return pending == null ? bytes : pending!.future;
  }
}

final _document = DocumentRecord(
  id: 'source',
  categoryKey: 'certificates',
  folderKey: 'seminars',
  title: 'Uploaded PDF',
  documentDate: DateTime.utc(2026),
  originalFileName: 'actual.pdf',
  mimeType: 'application/pdf',
  fileKind: 'pdf',
  extension: 'pdf',
  sizeBytes: 100,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _Documents extends DocumentService {
  _Documents(_Auth auth) : super(authService: auth);
  int reads = 0;
  int extracts = 0;
  @override
  bool get hasLoadedDocuments => true;
  @override
  bool get hasLoadedCategories => true;
  @override
  List<DocumentRecord> get documents => [_document];
  @override
  Future<void> load({bool force = false}) async {}
  @override
  Future<DocumentOcrResult> loadOcr(String documentId) async {
    reads++;
    return const DocumentOcrResult(status: DocumentOcrStatus.notProcessed);
  }

  @override
  Future<DocumentOcrResult> extractText(String documentId) async {
    extracts++;
    throw StateError('Preview must never extract text');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PrintingPlatform original;
  late _RasterPlatform platform;
  setUp(() {
    original = PrintingPlatform.instance;
    platform = _RasterPlatform();
    PrintingPlatform.instance = platform;
  });
  tearDown(() => PrintingPlatform.instance = original);

  for (final pageCount in [1, 3]) {
    testWidgets(
      '$pageCount source PDF pages are visual, scrollable, and never re-OCRed',
      (tester) async {
        platform.count = pageCount;
        final pdf = pw.Document();
        for (var i = 0; i < pageCount; i++) {
          pdf.addPage(
            pw.Page(build: (_) => pw.Text('Actual source page ${i + 1}')),
          );
        }
        final auth = _Auth()..bytes = await pdf.save();
        final docs = _Documents(auth);
        await tester.pumpWidget(
          _app(docs, DocumentPdfScreen(document: _document)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(PdfPreview), findsOneWidget);
        expect(platform.received, auth.bytes);
        expect(find.text('Page 1 of $pageCount'), findsOneWidget);
        if (pageCount > 1) {
          await tester.scrollUntilVisible(
            find.text('Page $pageCount of $pageCount'),
            300,
          );
        }
        expect(find.text('Page $pageCount of $pageCount'), findsOneWidget);
        expect(find.byType(Image), findsWidgets);
        expect(find.text('Extracted Text'), findsNothing);
        expect(docs.reads, 0);
        expect(docs.extracts, 0);
        expect(auth.paths, ['/api/v1/documents/source/content']);
        await tester.tap(find.text('Review extracted text'));
        await tester.pumpAndSettle();
        expect(find.byType(DocumentOcrScreen), findsOneWidget);
        expect(docs.reads, 1);
        expect(docs.extracts, 0);
        await tester.pumpWidget(const SizedBox());
        docs.dispose();
        auth.dispose();
      },
    );
  }

  testWidgets('scanned PDF uses unchanged source bytes without reading OCR', (
    tester,
  ) async {
    platform.count = 1;
    final pdf = pw.Document();
    pdf.addPage(pw.Page(build: (_) => pw.Image(pw.MemoryImage(_pagePng))));
    final auth = _Auth()..bytes = await pdf.save();
    final docs = _Documents(auth);
    await tester.pumpWidget(_app(docs, DocumentPdfScreen(document: _document)));
    await tester.pumpAndSettle();
    expect(platform.received, auth.bytes);
    expect(find.text('Page 1 of 1'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    expect(docs.reads, 0);
    expect(docs.extracts, 0);
    await tester.pumpWidget(const SizedBox());
    docs.dispose();
    auth.dispose();
  });

  testWidgets('file download has a loading state and safe retry', (
    tester,
  ) async {
    final auth = _Auth()..pending = Completer<Uint8List>();
    final docs = _Documents(auth);
    await tester.pumpWidget(_app(docs, DocumentPdfScreen(document: _document)));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    auth.pending!.completeError(
      const ApiException(code: 'NETWORK_ERROR', message: 'private host'),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Unable to load the source file'),
      findsOneWidget,
    );
    expect(find.textContaining('private host'), findsNothing);
    auth.pending = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(auth.paths.length, 2);
    expect(docs.extracts, 0);
    await tester.pumpWidget(const SizedBox());
    docs.dispose();
    auth.dispose();
  });

  testWidgets(
    'missing source is distinct from OCR and renderer failure is sanitized',
    (tester) async {
      final auth = _Auth()
        ..error = const ApiException(
          code: 'DOCUMENT_NOT_FOUND',
          statusCode: 404,
          message: 'private object key',
        );
      final docs = _Documents(auth);
      await tester.pumpWidget(
        _app(docs, DocumentPdfScreen(document: _document)),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('source file is no longer available'),
        findsOneWidget,
      );
      auth.error = null;
      platform.fail = true;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      // The plugin reports raster failures to Flutter as well as its onError UI.
      expect(tester.takeException(), isA<StateError>());
      expect(
        find.textContaining('This PDF could not be displayed'),
        findsOneWidget,
      );
      expect(find.textContaining('private renderer'), findsNothing);
      expect(docs.extracts, 0);
      await tester.pumpWidget(const SizedBox());
      docs.dispose();
      auth.dispose();
    },
  );

  for (final systemBack in [false, true]) {
    testWidgets(
      'Files opens visual PDF preview and ${systemBack ? 'system' : 'AppBar'} back returns once',
      (tester) async {
        final auth = _Auth();
        final docs = _Documents(auth);
        await tester.pumpWidget(
          _app(
            docs,
            const ViewFilesScreen(
              categoryKey: 'certificates',
              categoryName: 'Certificates',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('actual.pdf'));
        await tester.pumpAndSettle();
        expect(find.byType(DocumentPdfScreen), findsOneWidget);
        expect(find.byType(DocumentOcrScreen), findsNothing);
        expect(find.text('Back'), findsNothing);
        if (systemBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
        }
        await tester.pumpAndSettle();
        expect(find.byType(ViewFilesScreen), findsOneWidget);
        expect(find.byType(DocumentPdfScreen), findsNothing);
        await tester.pumpWidget(const SizedBox());
        docs.dispose();
        auth.dispose();
      },
    );
  }
}

Widget _app(DocumentService docs, Widget home) => DocumentScope(
  documentService: docs,
  child: MaterialApp(home: home),
);
