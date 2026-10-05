import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/screens/files/batch_review_screen.dart';
import 'package:proport_app/screens/files/document_ocr_screen.dart';
import 'package:proport_app/screens/files/files_screen.dart';
import 'package:proport_app/screens/portfolio/portfolio_preview_screen.dart';
import 'package:proport_app/screens/portfolio/models/portfolio_models.dart';
import 'package:proport_app/screens/portfolio/widgets/portfolio_documents_builder.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/batch_upload_queue.dart';
import 'package:proport_app/services/document_models.dart';
import 'package:proport_app/services/document_scope.dart';
import 'package:proport_app/services/document_service.dart';
import 'package:proport_app/services/secure_token_store.dart';
import 'package:proport_app/widgets/app_empty_state.dart';
import 'package:proport_app/widgets/app_skeleton.dart';

class _FakeTokenStore implements SecureTokenStore {
  @override
  Future<void> deleteRefreshToken() async {}
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> writeRefreshToken(String refreshToken) async {}
}

class _FakeAuthService extends AuthService {
  _FakeAuthService()
      : super(
          apiClient: ApiClient(baseUrl: 'http://localhost:3000'),
          tokenStore: _FakeTokenStore(),
        );
}

class _TestDocService extends DocumentService {
  _TestDocService({
    required super.authService,
    List<DocumentCategory> testCategories = const [],
    List<DocumentRecord> testDocuments = const [],
    bool isLoading = false,
    String? errorMessage,
    DocumentOcrResult? ocrResult,
    Completer<DocumentOcrResult>? loadCompleter,
    Completer<DocumentOcrResult>? extractCompleter,
  })  : _testCategories = testCategories,
        _testDocuments = testDocuments,
        _isLoading = isLoading,
        _errorMessage = errorMessage,
        _ocrResult = ocrResult,
        _loadCompleter = loadCompleter,
        _extractCompleter = extractCompleter;

  final List<DocumentCategory> _testCategories;
  final List<DocumentRecord> _testDocuments;
  final bool _isLoading;
  final String? _errorMessage;
  final DocumentOcrResult? _ocrResult;
  final Completer<DocumentOcrResult>? _loadCompleter;
  final Completer<DocumentOcrResult>? _extractCompleter;

  int extractCallCount = 0;

  @override
  List<DocumentCategory> get categories => _testCategories;

  @override
  List<DocumentRecord> get documents => _testDocuments;

  @override
  bool get hasLoadedCategories => true;

  @override
  bool get hasLoadedDocuments => true;

  @override
  bool get isLoading => _isLoading;

  @override
  String? get errorMessage => _errorMessage;

  @override
  Future<void> load({bool force = false}) async {}

  @override
  Future<DocumentOcrResult> loadOcr(String documentId) async {
    if (_loadCompleter != null) return _loadCompleter.future;
    return _ocrResult ??
        const DocumentOcrResult(status: DocumentOcrStatus.notProcessed);
  }

  @override
  Future<DocumentOcrResult> extractText(String documentId) async {
    extractCallCount++;
    if (_extractCompleter != null) return _extractCompleter.future;
    return _ocrResult ??
        const DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          reviewedText: 'New extracted text',
        );
  }
}

DocumentRecord _makeDocument({
  String id = 'doc-1',
  String name = 'doc.pdf',
  String categoryKey = 'certificates',
  String folderKey = 'seminars',
}) {
  return DocumentRecord(
    id: id,
    title: 'Test Document',
    categoryKey: categoryKey,
    folderKey: folderKey,
    originalFileName: name,
    mimeType: 'application/pdf',
    fileKind: 'pdf',
    extension: 'pdf',
    sizeBytes: 1024,
    documentDate: DateTime(2026, 1, 1),
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FilesScreen Empty & Skeleton States', () {
    testWidgets('shows FilesScreenSkeleton on initial loading', (tester) async {
      final auth = _FakeAuthService();
      final service = _TestDocService(
        authService: auth,
        isLoading: true,
        testCategories: const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentScope(
            documentService: service,
            child: const FilesScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(FilesScreenSkeleton), findsOneWidget);
      expect(find.byType(AppShimmer), findsWidgets);
    });

    testWidgets('shows full AppEmptyState when loaded with no files/categories', (
      tester,
    ) async {
      final auth = _FakeAuthService();
      final service = _TestDocService(
        authService: auth,
        isLoading: false,
        testCategories: const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentScope(
            documentService: service,
            child: const FilesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No files yet'), findsOneWidget);
      expect(find.text('Add File'), findsOneWidget);
      expect(
        find.text('Supports PDF, JPG, and PNG files.'),
        findsOneWidget,
      );
      expect(find.byType(AppEmptyIllustration), findsOneWidget);
    });

    testWidgets('shows search empty state and clears query with Clear Search button', (
      tester,
    ) async {
      final auth = _FakeAuthService();
      final categories = [
        const DocumentCategory(
          key: 'cv',
          name: 'Curriculum Vitae',
          folders: [DocumentFolder(key: 'resume', name: 'Resume')],
        ),
      ];
      final service = _TestDocService(
        authService: auth,
        testCategories: categories,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentScope(
            documentService: service,
            child: const FilesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Resume'), findsOneWidget);

      // Enter search text that does not match
      await tester.enterText(find.byType(TextField), 'nonexistent_query');
      await tester.pumpAndSettle();

      expect(find.text('No matching folders'), findsOneWidget);
      expect(find.text('Clear Search'), findsOneWidget);
      expect(find.text('Resume'), findsNothing);

      // Tap Clear Search CTA
      await tester.tap(find.text('Clear Search'));
      await tester.pumpAndSettle();

      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('No matching folders'), findsNothing);
    });

    testWidgets('empty category renders compact inline empty state', (tester) async {
      final auth = _FakeAuthService();
      final categories = [
        const DocumentCategory(
          key: 'empty_cat',
          name: 'Empty Category',
          folders: [],
        ),
      ];
      final service = _TestDocService(
        authService: auth,
        testCategories: categories,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentScope(
            documentService: service,
            child: const FilesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Empty Category'), findsOneWidget);
      expect(find.text('No folders in this category'), findsOneWidget);
    });
  });

  group('Portfolio Preview Loading & Empty States', () {
    testWidgets('PortfolioDocumentsBuilder renders PortfolioPreviewSkeleton while loading', (
      tester,
    ) async {
      final auth = _FakeAuthService();
      final service = _TestDocService(
        authService: auth,
        isLoading: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentScope(
            documentService: service,
            child: PortfolioDocumentsBuilder(
              builder: (docs) => const Text('Loaded'),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('portfolio-documents-loading')),
        findsOneWidget,
      );
      expect(find.byType(PortfolioPreviewSkeleton), findsOneWidget);
    });

    testWidgets('PortfolioPreviewScreen renders empty documents state', (
      tester,
    ) async {
      final auth = _FakeAuthService();
      final service = _TestDocService(
        authService: auth,
        testDocuments: const [],
      );
      const info = PortfolioInfo(
        fullName: 'Student Name',
        yearAndSection: '4A',
        schedule: 'MWF 9:00 AM',
        instructorName: 'Prof',
        course: 'BSCS',
        courseCode: 'CS101',
        semesterAndYear: '1st Sem 2026',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentScope(
            documentService: service,
            child: PortfolioPreviewScreen(portfolioInfo: info),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No stored documents to include yet.'), findsOneWidget);
    });
  });

  group('DocumentOcrScreen Skeleton & Text Retention', () {
    testWidgets('shows OcrTextSkeleton while loading OCR with no existing text', (
      tester,
    ) async {
      final auth = _FakeAuthService();
      final completer = Completer<DocumentOcrResult>();
      final doc = _makeDocument();
      final service = _TestDocService(
        authService: auth,
        testDocuments: [doc],
        loadCompleter: completer,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentScope(
            documentService: service,
            child: DocumentOcrScreen(document: doc),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(OcrTextSkeleton), findsOneWidget);

      completer.complete(
        const DocumentOcrResult(
          status: DocumentOcrStatus.notProcessed,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(OcrTextSkeleton), findsNothing);
      expect(find.text('No extracted text yet.'), findsOneWidget);
      expect(find.text('Extract Text'), findsOneWidget);
    });

    testWidgets('Extract Again preserves existing text in read-only mode and does NOT show skeleton', (
      tester,
    ) async {
      final auth = _FakeAuthService();
      final completer = Completer<DocumentOcrResult>();
      final doc = _makeDocument();
      final service = _TestDocService(
        authService: auth,
        testDocuments: [doc],
        ocrResult: const DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          reviewedText: 'Existing certificate transcript text',
        ),
        extractCompleter: completer,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentScope(
            documentService: service,
            child: DocumentOcrScreen(document: doc),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Existing text is displayed
      expect(find.text('Existing certificate transcript text'), findsOneWidget);

      // Tap Extract Again
      await tester.ensureVisible(find.byKey(const Key('extract-again-button')));
      await tester.tap(find.byKey(const Key('extract-again-button')));
      await tester.pumpAndSettle();

      // Confirm dialog
      expect(find.text('Extract text again?'), findsOneWidget);
      await tester.tap(find.text('Extract Again').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // In flight: skeleton must NOT replace the existing text!
      expect(find.byType(OcrTextSkeleton), findsNothing);
      expect(find.text('Existing certificate transcript text'), findsOneWidget);

      // TextField must be read-only while extracting
      final textField = tester.widget<TextField>(
        find.byKey(const Key('ocr-reviewed-text')),
      );
      expect(textField.readOnly, isTrue);

      // Complete extraction
      completer.complete(
        const DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          reviewedText: 'Updated transcript text',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Updated transcript text'), findsOneWidget);
    });
  });

  group('BatchReviewScreen Empty State', () {
    testWidgets('shows AppEmptyState with Go Back CTA when items is empty', (
      tester,
    ) async {
      final auth = _FakeAuthService();
      final service = _TestDocService(authService: auth);
      final queue = BatchUploadQueue(documentService: service);

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentScope(
            documentService: service,
            child: BatchReviewScreen(queue: queue),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No documents selected.'), findsOneWidget);
      expect(find.text('Go Back'), findsOneWidget);
      expect(find.byType(AppEmptyState), findsOneWidget);

      queue.dispose();
    });
  });

  group('AppShimmer Accessibility & Static Fallback', () {
    testWidgets('AppShimmer uses static color when animations are disabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: AppShimmer(
              child: AppSkeletonBox(width: 100, height: 20),
            ),
          ),
        ),
      );
      await tester.pump();

      // ShaderMask is not rendered when animations are disabled
      expect(find.byType(ShaderMask), findsNothing);
      expect(find.byType(AppSkeletonBox), findsOneWidget);
    });
  });
}
