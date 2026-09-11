import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/screens/files/add_file_screen.dart';
import 'package:proport_app/screens/files/files_screen.dart';
import 'package:proport_app/screens/files/view_files_screen.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/document_models.dart';
import 'package:proport_app/services/document_picker.dart';
import 'package:proport_app/services/document_scope.dart';
import 'package:proport_app/services/document_service.dart';
import 'package:proport_app/services/secure_token_store.dart';

void main() {
  testWidgets('Files renders backend categories and real folder counts', (
    tester,
  ) async {
    final service = _ScreenDocumentService(
      summary: const DocumentSummary(
        totalCount: 2,
        categoryCounts: {'certificates': 2},
        folderCounts: {'certificates/seminars': 2},
      ),
    );
    await tester.pumpWidget(_app(service, const FilesScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Certificates'), findsOneWidget);
    expect(find.text('Seminars'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Curriculum Vitae'), findsNothing);

    service.disposeWithAuth();
  });

  testWidgets('View Files shows an empty state without sample files', (
    tester,
  ) async {
    final service = _ScreenDocumentService();
    await tester.pumpWidget(_app(service, _viewFiles()));
    await tester.pumpAndSettle();

    expect(find.text('No files found.'), findsOneWidget);
    expect(find.text('sample_resume.pdf'), findsNothing);

    service.disposeWithAuth();
  });

  testWidgets(
    'View Files renders persisted metadata and deletes the owned item',
    (tester) async {
      final service = _ScreenDocumentService(documents: [_document()]);
      await tester.pumpWidget(_app(service, _viewFiles()));
      await tester.pumpAndSettle();

      expect(find.text('certificate.pdf'), findsOneWidget);
      expect(find.textContaining('2026'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(service.deletedIds, ['document-1']);
      expect(find.text('certificate.pdf'), findsNothing);
      expect(find.text('No files found.'), findsOneWidget);

      service.disposeWithAuth();
    },
  );

  testWidgets(
    'opens OCR, shows processing, saves edits, and reloads persisted text',
    (tester) async {
      final extraction = Completer<DocumentOcrResult>();
      final service = _ScreenDocumentService(
        documents: [_document()],
        extraction: extraction,
      );
      await tester.pumpWidget(_app(service, _viewFiles()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('certificate.pdf'));
      await tester.pumpAndSettle();
      expect(find.text('Extracted Text'), findsOneWidget);
      expect(find.text('Extract Text'), findsOneWidget);

      await tester.tap(find.text('Extract Text'));
      await tester.pump();
      expect(find.textContaining('Extracting text locally'), findsOneWidget);
      expect(service.extractionCalls, 1);

      extraction.complete(
        const DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          rawText: 'Raw certificate text',
          reviewedText: 'Raw certificate text',
          engine: 'tesseract.js',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Raw certificate text'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('ocr-reviewed-text')),
        'Corrected certificate text',
      );
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(service.savedText, 'Corrected certificate text');
      expect(find.text('Text changes saved.'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pumpAndSettle();
      await tester.tap(find.text('certificate.pdf'));
      await tester.pumpAndSettle();
      expect(find.text('Corrected certificate text'), findsOneWidget);

      service.disposeWithAuth();
    },
  );

  testWidgets('requires confirmation before replacing reviewed OCR text', (
    tester,
  ) async {
    final service = _ScreenDocumentService(
      documents: [_document()],
      ocr: const DocumentOcrResult(
        status: DocumentOcrStatus.ready,
        rawText: 'Original raw text',
        reviewedText: 'Reviewed text',
        engine: 'tesseract.js',
      ),
    );
    await tester.pumpWidget(_app(service, _viewFiles()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('certificate.pdf'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Extract Again'));
    await tester.tap(find.text('Extract Again'));
    await tester.pumpAndSettle();
    expect(find.text('Extract text again?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.extractionCalls, 0);

    service.disposeWithAuth();
  });

  testWidgets('shows safe scanned-PDF OCR errors without losing the file', (
    tester,
  ) async {
    final service = _ScreenDocumentService(
      documents: [_document()],
      extractionFailure: const ApiException(
        code: 'SCANNED_PDF_OCR_NOT_SUPPORTED',
        message:
            'This PDF has no embedded text. Scanned PDF OCR is not supported yet.',
        statusCode: 422,
      ),
    );
    await tester.pumpWidget(_app(service, _viewFiles()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('certificate.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extract Text'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('upload the page as JPG or PNG'),
      findsOneWidget,
    );
    expect(service.documents.single.id, 'document-1');
    expect(find.text('Try Again'), findsOneWidget);

    service.disposeWithAuth();
  });

  testWidgets('shows a safe authentication failure during OCR', (tester) async {
    final service = _ScreenDocumentService(
      documents: [_document()],
      extractionFailure: const ApiException(
        code: 'UNAUTHORIZED',
        message: 'Your session has expired. Please log in again.',
        statusCode: 401,
      ),
    );
    await tester.pumpWidget(_app(service, _viewFiles()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('certificate.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extract Text'));
    await tester.pumpAndSettle();

    expect(
      find.text('Your session has expired. Please log in again.'),
      findsOneWidget,
    );
    expect(service.documents.single.id, 'document-1');

    service.disposeWithAuth();
  });

  testWidgets('Add File picks a native file and uploads selected metadata', (
    tester,
  ) async {
    final service = _ScreenDocumentService();
    final bytes = Uint8List.fromList('%PDF-GradPort'.codeUnits);
    final picker = _FakePicker(
      PickedDocument(
        name: 'demo.pdf',
        mimeType: 'application/pdf',
        bytes: bytes,
      ),
    );
    await tester.pumpWidget(_app(service, AddFileScreen(filePicker: picker)));
    await tester.pumpAndSettle();

    await _completeUploadForm(tester);
    await tester.tap(find.text('Add File'));
    await tester.pump();

    expect(picker.calls, 1);
    expect(service.uploadedFile?.name, 'demo.pdf');
    expect(service.uploadedFile?.bytes, same(bytes));
    expect(service.uploadedCategoryKey, 'certificates');
    expect(service.uploadedFolderKey, 'seminars');
    expect(service.uploadedTitle, 'Demo Certificate');
    expect(service.uploadedDate, isNotNull);
    expect(service.summary.totalCount, 1);

    service.disposeWithAuth();
  });

  testWidgets(
    'Add File shows a safe API error and does not add failed uploads',
    (tester) async {
      final service = _ScreenDocumentService(
        uploadFailure: const ApiException(
          code: 'DOCUMENT_UNAVAILABLE',
          message: 'Documents are temporarily unavailable. Please try again.',
          statusCode: 503,
        ),
      );
      final picker = _FakePicker(
        PickedDocument(
          name: 'demo.pdf',
          mimeType: 'application/pdf',
          bytes: Uint8List.fromList('%PDF-GradPort'.codeUnits),
        ),
      );
      await tester.pumpWidget(_app(service, AddFileScreen(filePicker: picker)));
      await tester.pumpAndSettle();

      await _completeUploadForm(tester);
      await tester.tap(find.text('Add File'));
      await tester.pump();

      expect(
        find.text('Documents are temporarily unavailable. Please try again.'),
        findsOneWidget,
      );
      expect(service.documents, isEmpty);
      expect(service.summary.totalCount, 0);

      service.disposeWithAuth();
    },
  );

  testWidgets('Add File rejects unsupported and oversized picker results', (
    tester,
  ) async {
    final service = _ScreenDocumentService();
    final unsupported = _FakePicker(
      PickedDocument(
        name: 'notes.txt',
        mimeType: 'text/plain',
        bytes: Uint8List(1),
      ),
    );
    await tester.pumpWidget(
      _app(service, AddFileScreen(filePicker: unsupported)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tap to upload file'));
    await tester.pump();
    expect(
      find.text('Please select a PDF, JPG, JPEG, or PNG file.'),
      findsOneWidget,
    );
    expect(find.text('notes.txt'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    service.disposeWithAuth();

    final oversizedService = _ScreenDocumentService();
    final oversized = _FakePicker(
      PickedDocument(
        name: 'large.pdf',
        mimeType: 'application/pdf',
        bytes: Uint8List(DocumentService.maxUploadBytes + 1),
      ),
    );
    await tester.pumpWidget(
      _app(oversizedService, AddFileScreen(filePicker: oversized)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tap to upload file'));
    await tester.pump();
    expect(
      find.text('The selected file exceeds the 15 MB upload limit.'),
      findsOneWidget,
    );
    expect(find.text('large.pdf'), findsNothing);

    oversizedService.disposeWithAuth();
  });
}

Widget _viewFiles() => const ViewFilesScreen(
  categoryKey: 'certificates',
  categoryName: 'Certificates',
  folderKey: 'seminars',
  folderName: 'Seminars',
);

Widget _app(DocumentService service, Widget child) => DocumentScope(
  documentService: service,
  child: MaterialApp(home: child),
);

Future<void> _completeUploadForm(WidgetTester tester) async {
  await tester.tap(find.text('Tap to upload file'));
  await tester.pump();

  await tester.tap(find.byType(DropdownButton<String>).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Certificates').last);
  await tester.pumpAndSettle();

  await tester.tap(find.byType(DropdownButton<String>).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Seminars').last);
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField).first, 'Demo Certificate');
  await tester.tap(find.text('MM/DD/YYYY'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Add File'));
}

class _FakePicker implements DocumentPicker {
  _FakePicker(this.result);

  final PickedDocument? result;
  int calls = 0;

  @override
  Future<PickedDocument?> pickDocument() async {
    calls++;
    return result;
  }
}

class _ScreenDocumentService extends DocumentService {
  factory _ScreenDocumentService({
    List<DocumentRecord> documents = const [],
    DocumentSummary summary = DocumentSummary.empty,
    ApiException? uploadFailure,
    DocumentOcrResult ocr = const DocumentOcrResult(
      status: DocumentOcrStatus.notProcessed,
    ),
    Completer<DocumentOcrResult>? extraction,
    ApiException? extractionFailure,
  }) {
    final auth = _NoopAuthService();
    return _ScreenDocumentService._(
      auth,
      documents: documents,
      summary: summary,
      uploadFailure: uploadFailure,
      ocr: ocr,
      extraction: extraction,
      extractionFailure: extractionFailure,
    );
  }

  _ScreenDocumentService._(
    this._auth, {
    required List<DocumentRecord> documents,
    required DocumentSummary summary,
    required this.uploadFailure,
    required DocumentOcrResult ocr,
    required this.extraction,
    required this.extractionFailure,
  }) : _documents = documents,
       _summary = summary,
       _ocr = ocr,
       super(authService: _auth);

  static const _categories = [
    DocumentCategory(
      key: 'certificates',
      name: 'Certificates',
      folders: [DocumentFolder(key: 'seminars', name: 'Seminars')],
    ),
  ];

  final _NoopAuthService _auth;
  List<DocumentRecord> _documents;
  DocumentSummary _summary;
  final ApiException? uploadFailure;
  DocumentOcrResult _ocr;
  final Completer<DocumentOcrResult>? extraction;
  final ApiException? extractionFailure;
  int extractionCalls = 0;
  String? savedText;
  final List<String> deletedIds = [];
  PickedDocument? uploadedFile;
  String? uploadedCategoryKey;
  String? uploadedFolderKey;
  String? uploadedTitle;
  DateTime? uploadedDate;

  @override
  List<DocumentCategory> get categories => _categories;

  @override
  List<DocumentRecord> get documents => List.unmodifiable(_documents);

  @override
  DocumentSummary get summary => _summary;

  @override
  bool get hasLoadedDocuments => true;

  @override
  bool get hasLoadedCategories => true;

  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => null;

  @override
  Future<void> load({bool force = false}) async {}

  @override
  Future<DocumentRecord> upload({
    required PickedDocument file,
    required String categoryKey,
    required String folderKey,
    required String title,
    required DateTime documentDate,
    String? description,
    String? reflection,
  }) async {
    final failure = uploadFailure;
    if (failure != null) throw failure;
    uploadedFile = file;
    uploadedCategoryKey = categoryKey;
    uploadedFolderKey = folderKey;
    uploadedTitle = title;
    uploadedDate = documentDate;
    final created = _document(fileName: file.name);
    _documents = [created, ..._documents];
    _summary = _summary.adding(created);
    notifyListeners();
    return created;
  }

  @override
  Future<void> delete(String documentId) async {
    deletedIds.add(documentId);
    final matches = _documents.where((value) => value.id == documentId);
    final existing = matches.isEmpty ? null : matches.first;
    _documents = _documents
        .where((value) => value.id != documentId)
        .toList(growable: false);
    if (existing != null) _summary = _summary.removing(existing);
    notifyListeners();
  }

  @override
  Future<DocumentOcrResult> loadOcr(String documentId) async => _ocr;

  @override
  Future<DocumentOcrResult> extractText(String documentId) async {
    extractionCalls++;
    final failure = extractionFailure;
    if (failure != null) {
      _ocr = const DocumentOcrResult(status: DocumentOcrStatus.failed);
      throw failure;
    }
    final result = extraction == null
        ? const DocumentOcrResult(
            status: DocumentOcrStatus.ready,
            rawText: 'Extracted test text',
            reviewedText: 'Extracted test text',
            engine: 'tesseract.js',
          )
        : await extraction!.future;
    _ocr = result;
    notifyListeners();
    return result;
  }

  @override
  Future<DocumentOcrResult> saveReviewedText(
    String documentId,
    String reviewedText,
  ) async {
    savedText = reviewedText;
    _ocr = DocumentOcrResult(
      status: DocumentOcrStatus.ready,
      rawText: _ocr.rawText,
      reviewedText: reviewedText,
      engine: _ocr.engine,
    );
    notifyListeners();
    return _ocr;
  }

  void disposeWithAuth() {
    dispose();
    _auth.dispose();
  }
}

class _NoopAuthService extends AuthService {
  _NoopAuthService()
    : super(
        apiClient: ApiClient(baseUrl: 'http://example.test:3000'),
        tokenStore: _NoopTokenStore(),
      );
}

class _NoopTokenStore implements SecureTokenStore {
  @override
  Future<void> deleteRefreshToken() async {}

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> writeRefreshToken(String refreshToken) async {}
}

DocumentRecord _document({String fileName = 'certificate.pdf'}) =>
    DocumentRecord(
      id: 'document-1',
      categoryKey: 'certificates',
      folderKey: 'seminars',
      title: 'Certificate',
      documentDate: DateTime(2026, 9, 11),
      originalFileName: fileName,
      mimeType: 'application/pdf',
      fileKind: 'pdf',
      extension: 'pdf',
      sizeBytes: 128,
      createdAt: DateTime(2026, 9, 11),
      updatedAt: DateTime(2026, 9, 11),
    );
