import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/screens/auth/login_screen.dart';
import 'package:proport_app/screens/files/document_ocr_screen.dart';
import 'package:proport_app/screens/files/view_files_screen.dart';
import 'package:proport_app/screens/portfolio/models/portfolio_models.dart';
import 'package:proport_app/screens/portfolio/portfolio_preview_screen.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_scope.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/document_models.dart';
import 'package:proport_app/services/document_scope.dart';
import 'package:proport_app/services/document_service.dart';
import 'package:proport_app/services/secure_token_store.dart';
import 'package:proport_app/widgets/document_image_preview.dart';

final samplePngBytes = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

class _TestTokenStore implements SecureTokenStore {
  @override
  Future<void> deleteRefreshToken() async {}
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> writeRefreshToken(String refreshToken) async {}
}

class _MockAuthService extends AuthService {
  _MockAuthService({this.contentBytes, this.throwOnGet = false})
    : super(
        apiClient: ApiClient(baseUrl: 'http://localhost:3000'),
        tokenStore: _TestTokenStore(),
      );

  final Uint8List? contentBytes;
  final bool throwOnGet;
  final List<String> requestedPaths = [];

  @override
  Future<Uint8List> authenticatedGetBytes(
    String path, {
    Duration? requestTimeout,
  }) async {
    requestedPaths.add(path);
    if (throwOnGet) {
      throw const ApiException(
        code: 'NETWORK_ERROR',
        message: 'Unable to reach server.',
      );
    }
    return contentBytes ?? samplePngBytes;
  }
}

class _TestDocumentService extends DocumentService {
  _TestDocumentService({
    required _MockAuthService authService,
    List<DocumentRecord> documents = const [],
    this.ocrResult = const DocumentOcrResult(status: DocumentOcrStatus.notProcessed),
  })  : _docs = documents,
        super(authService: authService);

  final List<DocumentRecord> _docs;
  DocumentOcrResult ocrResult;
  int extractOcrCalls = 0;
  int loadOcrCalls = 0;
  String? savedReviewedText;
  Future<DocumentOcrResult> Function(String documentId)? onExtractText;

  @override
  List<DocumentRecord> get documents => _docs;

  @override
  bool get hasLoadedDocuments => true;

  @override
  bool get hasLoadedCategories => true;

  @override
  List<DocumentCategory> get categories => const [
        DocumentCategory(
          key: 'certificates',
          name: 'Certificates',
          folders: [
            DocumentFolder(key: 'seminars', name: 'Seminars'),
          ],
        ),
      ];

  @override
  DocumentSummary get summary => DocumentSummary(
        totalCount: _docs.length,
        categoryCounts: {'certificates': _docs.length},
        folderCounts: {'certificates/seminars': _docs.length},
      );

  @override
  Future<void> load({bool force = false}) async {
    // No-op in test so it doesn't call real API endpoints
  }

  @override
  Future<DocumentOcrResult> loadOcr(String documentId) async {
    loadOcrCalls++;
    return ocrResult;
  }

  @override
  Future<DocumentOcrResult> extractText(String documentId) async {
    extractOcrCalls++;
    if (onExtractText != null) {
      return onExtractText!(documentId);
    }
    ocrResult = const DocumentOcrResult(
      status: DocumentOcrStatus.ready,
      rawText: 'Newly extracted text',
      reviewedText: 'Newly extracted text',
    );
    return ocrResult;
  }

  @override
  Future<DocumentOcrResult> saveReviewedText(
    String documentId,
    String reviewedText,
  ) async {
    savedReviewedText = reviewedText;
    ocrResult = DocumentOcrResult(
      status: DocumentOcrStatus.ready,
      reviewedText: reviewedText,
    );
    return ocrResult;
  }
}

DocumentRecord _makeImageDoc({
  String id = 'doc-img-1',
  String fileName = 'certificate.png',
  List<DocumentAttachmentRecord>? attachments,
}) {
  return DocumentRecord(
    id: id,
    categoryKey: 'certificates',
    folderKey: 'seminars',
    title: 'Seminar Certificate',
    documentDate: DateTime(2026, 9, 20),
    originalFileName: fileName,
    mimeType: 'image/png',
    fileKind: 'image',
    extension: 'png',
    sizeBytes: 1024,
    createdAt: DateTime(2026, 9, 20),
    updatedAt: DateTime(2026, 9, 20),
    attachments: attachments,
  );
}

DocumentRecord _makePdfDoc({
  String id = 'doc-pdf-1',
  String fileName = 'sample.pdf',
}) {
  return DocumentRecord(
    id: id,
    categoryKey: 'certificates',
    folderKey: 'seminars',
    title: 'PDF Document',
    documentDate: DateTime(2026, 9, 20),
    originalFileName: fileName,
    mimeType: 'application/pdf',
    fileKind: 'pdf',
    extension: 'pdf',
    sizeBytes: 2048,
    createdAt: DateTime(2026, 9, 20),
    updatedAt: DateTime(2026, 9, 20),
  );
}

Widget _wrapWithScope({
  required DocumentService documentService,
  required Widget child,
}) {
  return MaterialApp(
    home: DocumentScope(
      documentService: documentService,
      child: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Goal 1: Portfolio Preview Shows Actual Documents', () {
    testWidgets('image document displays actual visual preview with contain fit', (
      tester,
    ) async {
      final auth = _MockAuthService(contentBytes: samplePngBytes);
      final doc = _makeImageDoc();
      final docService = _TestDocumentService(
        authService: auth,
        documents: [doc],
      );

      const portfolioInfo = PortfolioInfo(
        fullName: 'John Lloyd',
        yearAndSection: '4BSIT-1',
        schedule: 'Mon 8-10',
        instructorName: 'Prof',
        course: 'BSIT',
        courseCode: 'IT101',
        semesterAndYear: '2026',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentScope(
            documentService: docService,
            child: const PortfolioPreviewScreen(portfolioInfo: portfolioInfo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Document title and metadata visible
      expect(find.text('Seminar Certificate'), findsOneWidget);
      expect(find.text('certificate.png'), findsOneWidget);

      // DocumentImagePreview is rendered
      expect(find.byType(DocumentImagePreview), findsOneWidget);

      // Path requested was primary content (Page 1)
      expect(auth.requestedPaths, ['/api/v1/documents/doc-img-1/content']);
    });

    testWidgets('one failed image falls back gracefully without blocking preview', (
      tester,
    ) async {
      final auth = _MockAuthService(throwOnGet: true);
      final doc = _makeImageDoc();
      final docService = _TestDocumentService(
        authService: auth,
        documents: [doc],
      );

      const portfolioInfo = PortfolioInfo(
        fullName: 'John Lloyd',
        yearAndSection: '4BSIT-1',
        schedule: 'Mon 8-10',
        instructorName: 'Prof',
        course: 'BSIT',
        courseCode: 'IT101',
        semesterAndYear: '2026',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentScope(
            documentService: docService,
            child: const PortfolioPreviewScreen(portfolioInfo: portfolioInfo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Preview sheet and student info still rendered
      expect(find.text('John Lloyd'), findsOneWidget);
      expect(find.text('Seminar Certificate'), findsOneWidget);

      // Broken image fallback rendered
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    });

    testWidgets('PDF document keeps clear PDF representation in Portfolio Preview', (
      tester,
    ) async {
      final auth = _MockAuthService();
      final doc = _makePdfDoc();
      final docService = _TestDocumentService(
        authService: auth,
        documents: [doc],
      );

      const portfolioInfo = PortfolioInfo(
        fullName: 'John Lloyd',
        yearAndSection: '4BSIT-1',
        schedule: 'Mon 8-10',
        instructorName: 'Prof',
        course: 'BSIT',
        courseCode: 'IT101',
        semesterAndYear: '2026',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentScope(
            documentService: docService,
            child: const PortfolioPreviewScreen(portfolioInfo: portfolioInfo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PDF Document'), findsOneWidget);
      expect(find.text('sample.pdf'), findsOneWidget);
      expect(find.byIcon(Icons.picture_as_pdf_rounded), findsWidgets);
      // Did not attempt to render image preview for PDF
      expect(find.byType(DocumentImagePreview), findsNothing);
    });
  });

  group('Goal 2: Files List Real Image Thumbnails', () {
    testWidgets('image document in Files displays DocumentThumbnail with page 1 primary endpoint', (
      tester,
    ) async {
      final auth = _MockAuthService(contentBytes: samplePngBytes);
      final doc = _makeImageDoc();
      final docService = _TestDocumentService(
        authService: auth,
        documents: [doc],
      );

      await tester.pumpWidget(
        _wrapWithScope(
          documentService: docService,
          child: const ViewFilesScreen(
            categoryKey: 'certificates',
            categoryName: 'Certificates',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('certificate.png'), findsOneWidget);
      expect(find.byType(DocumentThumbnail), findsOneWidget);
      // Uses primary content endpoint without attachmentId
      expect(auth.requestedPaths, ['/api/v1/documents/doc-img-1/content']);
    });

    testWidgets('failed thumbnail retrieval falls back safely to icon', (
      tester,
    ) async {
      final auth = _MockAuthService(throwOnGet: true);
      final doc = _makeImageDoc();
      final docService = _TestDocumentService(
        authService: auth,
        documents: [doc],
      );

      await tester.pumpWidget(
        _wrapWithScope(
          documentService: docService,
          child: const ViewFilesScreen(
            categoryKey: 'certificates',
            categoryName: 'Certificates',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('certificate.png'), findsOneWidget);
      expect(find.byType(DocumentThumbnail), findsOneWidget);
      // Fallback icon inside thumbnail
      expect(find.byIcon(Icons.image_rounded), findsOneWidget);
    });

    testWidgets('PDF document in Files displays PDF icon without image thumbnail', (
      tester,
    ) async {
      final auth = _MockAuthService();
      final doc = _makePdfDoc();
      final docService = _TestDocumentService(
        authService: auth,
        documents: [doc],
      );

      await tester.pumpWidget(
        _wrapWithScope(
          documentService: docService,
          child: const ViewFilesScreen(
            categoryKey: 'certificates',
            categoryName: 'Certificates',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('sample.pdf'), findsOneWidget);
      expect(find.byType(DocumentThumbnail), findsNothing);
      expect(find.byIcon(Icons.picture_as_pdf_rounded), findsOneWidget);
    });
  });

  group('Goal 3: Document Detail Displays Image Immediately & Handles Stored OCR', () {
    testWidgets('opening image document displays actual image immediately without tapping Extract', (
      tester,
    ) async {
      final auth = _MockAuthService(contentBytes: samplePngBytes);
      final doc = _makeImageDoc();
      final docService = _TestDocumentService(
        authService: auth,
        documents: [doc],
        ocrResult: const DocumentOcrResult(status: DocumentOcrStatus.notProcessed),
      );

      await tester.pumpWidget(
        _wrapWithScope(
          documentService: docService,
          child: DocumentOcrScreen(document: doc),
        ),
      );
      await tester.pumpAndSettle();

      // Actual image preview is rendered immediately
      expect(find.byType(DocumentImagePreview), findsOneWidget);
      expect(find.text('Seminar Certificate'), findsOneWidget);
      expect(find.text('certificate.png'), findsOneWidget);

      // Section header is present
      expect(find.text('Extracted Text'), findsOneWidget);
      // No OCR text yet state
      expect(find.text('No extracted text yet.'), findsOneWidget);
      expect(find.text('Extract Text'), findsOneWidget);

      // 0 extraction calls made
      expect(docService.extractOcrCalls, 0);
    });

    testWidgets('saved OCR text displays automatically with zero extraction requests', (
      tester,
    ) async {
      final auth = _MockAuthService(contentBytes: samplePngBytes);
      final doc = _makeImageDoc();
      final docService = _TestDocumentService(
        authService: auth,
        documents: [doc],
        ocrResult: const DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          reviewedText: 'Persisted certificate transcript text',
        ),
      );

      await tester.pumpWidget(
        _wrapWithScope(
          documentService: docService,
          child: DocumentOcrScreen(document: doc),
        ),
      );
      await tester.pumpAndSettle();

      // Image is visible
      expect(find.byType(DocumentImagePreview), findsOneWidget);

      // Saved text is displayed automatically
      expect(find.text('Persisted certificate transcript text'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);
      expect(find.text('Extract Again'), findsOneWidget);

      // Extract Text is NOT visible because OCR is already ready
      expect(find.text('Extract Text'), findsNothing);

      // Zero new extraction requests triggered
      expect(docService.extractOcrCalls, 0);
      // loadOcr called once to retrieve database record
      expect(docService.loadOcrCalls, 1);
    });

    testWidgets('Extract Again prompts and runs extraction only upon explicit tap', (
      tester,
    ) async {
      final auth = _MockAuthService(contentBytes: samplePngBytes);
      final doc = _makeImageDoc();
      final docService = _TestDocumentService(
        authService: auth,
        documents: [doc],
        ocrResult: const DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          reviewedText: 'Existing text',
        ),
      );

      await tester.pumpWidget(
        _wrapWithScope(
          documentService: docService,
          child: DocumentOcrScreen(document: doc),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Extract Again
      await tester.ensureVisible(find.text('Extract Again'));
      await tester.tap(find.text('Extract Again'));
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.text('Extract text again?'), findsOneWidget);

      // Confirm extraction
      await tester.tap(find.text('Extract Again').last);
      await tester.pumpAndSettle();

      // Explicit rerun occurred
      expect(docService.extractOcrCalls, 1);
      expect(find.text('Newly extracted text'), findsOneWidget);
    });

    testWidgets('Extract Again dialog cancel does not trigger extraction', (
      tester,
    ) async {
      final auth = _MockAuthService(contentBytes: samplePngBytes);
      final doc = _makeImageDoc();
      final docService = _TestDocumentService(
        authService: auth,
        documents: [doc],
        ocrResult: const DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          reviewedText: 'Existing text',
        ),
      );

      await tester.pumpWidget(
        _wrapWithScope(
          documentService: docService,
          child: DocumentOcrScreen(document: doc),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Extract Again'));
      await tester.tap(find.text('Extract Again'));
      await tester.pumpAndSettle();

      expect(find.text('Extract text again?'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog is dismissed, 0 extraction calls made
      expect(find.text('Extract text again?'), findsNothing);
      expect(docService.extractOcrCalls, 0);
      expect(find.text('Existing text'), findsOneWidget);
    });

    testWidgets('Extract Again displays extracting state with spinner and prevents duplicate taps', (
      tester,
    ) async {
      final auth = _MockAuthService(contentBytes: samplePngBytes);
      final doc = _makeImageDoc();
      final completer = Completer<DocumentOcrResult>();
      final docService = _TestDocumentService(
        authService: auth,
        documents: [doc],
        ocrResult: const DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          reviewedText: 'Existing text',
        ),
      );
      docService.onExtractText = (_) => completer.future;

      await tester.pumpWidget(
        _wrapWithScope(
          documentService: docService,
          child: DocumentOcrScreen(document: doc),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Extract Again'));
      await tester.tap(find.text('Extract Again'));
      await tester.pumpAndSettle();

      // Confirm extraction
      await tester.tap(find.text('Extract Again').last);
      // Pump one frame to start extraction without completing the future
      await tester.pump();

      // In-flight state: Extracting... with spinner
      expect(find.text('Extracting...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(docService.extractOcrCalls, 1);

      // Attempt repeated tap while processing
      await tester.tap(find.text('Extracting...'));
      await tester.pump();
      // Should NOT trigger duplicate calls
      expect(docService.extractOcrCalls, 1);

      // Complete extraction
      completer.complete(
        const DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          rawText: 'Brand new text',
          reviewedText: 'Brand new text',
        ),
      );
      await tester.pumpAndSettle();

      // Finished: shows normal button and new text
      expect(find.text('Extract Again'), findsOneWidget);
      expect(find.text('Brand new text'), findsOneWidget);
    });

    testWidgets('Extract Again failure preserves user-edited text in controller and displays error', (
      tester,
    ) async {
      final auth = _MockAuthService(contentBytes: samplePngBytes);
      final doc = _makeImageDoc();
      final docService = _TestDocumentService(
        authService: auth,
        documents: [doc],
        ocrResult: const DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          reviewedText: 'Initial text',
        ),
      );
      docService.onExtractText = (_) => throw const ApiException(
            code: 'OCR_TIMEOUT',
            message: 'Text extraction timed out. Please try again.',
          );

      await tester.pumpWidget(
        _wrapWithScope(
          documentService: docService,
          child: DocumentOcrScreen(document: doc),
        ),
      );
      await tester.pumpAndSettle();

      // User modifies text locally in the text field
      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);
      await tester.enterText(textFieldFinder, 'User draft before failed re-extraction');
      await tester.pumpAndSettle();

      // Tap Extract Again and confirm
      await tester.ensureVisible(find.text('Extract Again'));
      await tester.tap(find.text('Extract Again'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Extract Again').last);
      await tester.pumpAndSettle();

      // Verify error feedback is displayed
      expect(find.text('Text extraction timed out. Please try again.'), findsOneWidget);

      // CRITICAL: User-edited text must NOT be erased or overwritten with initial text
      expect(find.text('User draft before failed re-extraction'), findsOneWidget);
      expect(find.text('Initial text'), findsNothing);

      // Button is enabled again
      expect(find.text('Extract Again'), findsOneWidget);
    });

    testWidgets('Extract Again receives OCR_BUSY: preserves text, shows retry message, and keeps retry action enabled', (
      tester,
    ) async {
      final auth = _MockAuthService(contentBytes: samplePngBytes);
      final doc = _makeImageDoc();
      final docService = _TestDocumentService(
        authService: auth,
        documents: [doc],
        ocrResult: const DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          rawText: 'Original extracted text',
          reviewedText: 'Original reviewed text',
        ),
      );

      docService.onExtractText = (_) => throw const ApiException(
            statusCode: 503,
            code: 'OCR_BUSY',
            message: 'The server is busy processing another document. Please try again in a few moments.',
          );

      await tester.pumpWidget(
        _wrapWithScope(
          documentService: docService,
          child: DocumentOcrScreen(document: doc),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Original reviewed text'), findsOneWidget);

      await tester.ensureVisible(find.text('Extract Again'));
      await tester.tap(find.text('Extract Again'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Extract Again').last);
      await tester.pumpAndSettle();

      expect(
        find.text('The server is busy processing another document. Please try again in a few moments.'),
        findsOneWidget,
      );

      expect(find.text('Original reviewed text'), findsOneWidget);
      expect(find.text('Extract Again'), findsOneWidget);
    });
  });

  group('Goal 4: Multi-Page Document Viewing', () {
    testWidgets('multi-page document displays Page 1 primary content and Page 2+ attachments in order', (
      tester,
    ) async {
      final auth = _MockAuthService(contentBytes: samplePngBytes);
      final attachments = [
        const DocumentAttachmentRecord(
          id: 'att-1',
          originalFileName: 'page1.png',
          mimeType: 'image/png',
          fileKind: 'image',
          extension: 'png',
          sizeBytes: 1024,
          order: 0,
        ),
        const DocumentAttachmentRecord(
          id: 'att-2',
          originalFileName: 'page2.png',
          mimeType: 'image/png',
          fileKind: 'image',
          extension: 'png',
          sizeBytes: 1024,
          order: 1,
        ),
      ];

      final doc = _makeImageDoc(attachments: attachments);
      final docService = _TestDocumentService(
        authService: auth,
        documents: [doc],
      );

      await tester.pumpWidget(
        _wrapWithScope(
          documentService: docService,
          child: DocumentOcrScreen(document: doc),
        ),
      );
      await tester.pumpAndSettle();

      // Page indicator displays "Page 1 of 2"
      expect(find.text('Page 1 of 2'), findsOneWidget);

      // Primary document content requested first
      expect(auth.requestedPaths.contains('/api/v1/documents/doc-img-1/content'), isTrue);

      // Navigate to page 2
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();

      expect(find.text('Page 2 of 2'), findsOneWidget);
      // Attachment content requested for page 2
      expect(
        auth.requestedPaths.contains('/api/v1/documents/doc-img-1/attachments/att-2/content'),
        isTrue,
      );
    });
  });

  group('Goal 5: Login Screen Title & Subtitle Alignment', () {
    testWidgets('Login screen displays centered "Log In", does NOT display "Welcome Back!" or old subtitle', (
      tester,
    ) async {
      final auth = _MockAuthService();

      await tester.pumpWidget(
        MaterialApp(
          home: AuthScope(
            authService: auth,
            child: const LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // "Log In" appears for title and button
      expect(find.text('Log In'), findsNWidgets(2));
      // "Welcome Back!" is NOT visible
      expect(find.text('Welcome Back!'), findsNothing);

      // Old subtitle is removed
      expect(find.text('Sign in to continue your journey.'), findsNothing);

      // Verify centered title alignment
      final titleWidget = tester.widget<Text>(find.text('Log In').first);
      expect(titleWidget.textAlign, TextAlign.center);

      // Essential login components remain present
      expect(find.byType(TextField), findsNWidgets(2)); // Email & Password
      expect(find.byKey(const Key('loginButton')), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);
      expect(find.text('Sign Up'), findsOneWidget);
    });
  });

  group('Content Caching & Eviction Tests (Correction 4 & 6)', () {
    testWidgets('repeated widget rebuilds do not re-request bytes when cache is valid', (
      tester,
    ) async {
      final auth = _MockAuthService(contentBytes: samplePngBytes);
      final doc = _makeImageDoc();
      final docService = _TestDocumentService(
        authService: auth,
        documents: [doc],
      );

      await tester.pumpWidget(
        _wrapWithScope(
          documentService: docService,
          child: DocumentImagePreview(documentId: doc.id),
        ),
      );
      await tester.pumpAndSettle();

      expect(auth.requestedPaths.length, 1);

      // Rebuild with same documentId
      await tester.pumpWidget(
        _wrapWithScope(
          documentService: docService,
          child: DocumentImagePreview(documentId: doc.id),
        ),
      );
      await tester.pumpAndSettle();

      // No second network request made!
      expect(auth.requestedPaths.length, 1);
    });

    test('deterministic eviction occurs when cache limit exceeds maxCachedDocuments (30)', () async {
      final auth = _MockAuthService(contentBytes: samplePngBytes);
      final docService = DocumentService(authService: auth);

      // Fill 30 entries
      for (int i = 1; i <= 30; i++) {
        docService.setCachedContent('doc-$i', samplePngBytes);
      }
      expect(docService.getCachedContent('doc-1'), isNotNull);
      expect(docService.getCachedContent('doc-30'), isNotNull);

      // Add 31st entry -> should evict doc-1 (oldest)
      docService.setCachedContent('doc-31', samplePngBytes);
      expect(docService.getCachedContent('doc-1'), isNull);
      expect(docService.getCachedContent('doc-31'), isNotNull);
    });

    test('deterministic byte ceiling eviction occurs when total bytes exceed maxCachedBytes (30 MiB)', () async {
      final auth = _MockAuthService();
      final docService = DocumentService(authService: auth);

      // 16 MiB payload (16 * 1024 * 1024 bytes)
      final large1 = Uint8List(16 * 1024 * 1024);
      final large2 = Uint8List(16 * 1024 * 1024);

      docService.setCachedContent('large-1', large1);
      expect(docService.getCachedContent('large-1'), isNotNull);
      expect(docService.currentCachedBytes, 16 * 1024 * 1024);

      // Adding large2 brings requested total to 32 MiB > 30 MiB ceiling
      // large-1 must be evicted to stay under 30 MiB
      docService.setCachedContent('large-2', large2);
      expect(docService.getCachedContent('large-1'), isNull);
      expect(docService.getCachedContent('large-2'), isNotNull);
      expect(docService.currentCachedBytes, 16 * 1024 * 1024);
      expect(docService.currentCachedBytes <= DocumentService.maxCachedBytes, isTrue);
    });

    testWidgets('DocumentThumbnail passes safe decode cacheWidth (140) to DocumentImagePreview', (
      tester,
    ) async {
      final auth = _MockAuthService(contentBytes: samplePngBytes);
      final doc = _makeImageDoc();
      final docService = _TestDocumentService(
        authService: auth,
        documents: [doc],
      );

      await tester.pumpWidget(
        _wrapWithScope(
          documentService: docService,
          child: DocumentThumbnail(documentId: doc.id),
        ),
      );
      await tester.pumpAndSettle();

      final previewWidget = tester.widget<DocumentImagePreview>(
        find.byType(DocumentImagePreview),
      );
      expect(previewWidget.cacheWidth, 140);
      expect(previewWidget.cacheHeight, isNull); // Preserves aspect ratio!
    });
  });
}
