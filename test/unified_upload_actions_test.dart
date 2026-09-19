import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/screens/files/add_file_screen.dart';
import 'package:proport_app/screens/files/batch_review_screen.dart';
import 'package:proport_app/screens/main_screen.dart';
import 'package:proport_app/screens/portfolio/models/portfolio_models.dart';
import 'package:proport_app/screens/portfolio/portfolio_export_screen.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_models.dart';
import 'package:proport_app/services/auth_scope.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/document_models.dart';
import 'package:proport_app/services/document_picker.dart';
import 'package:proport_app/services/document_scope.dart';
import 'package:proport_app/services/document_service.dart';
import 'package:proport_app/services/portfolio_export_service.dart';
import 'package:proport_app/services/portfolio_scope.dart';
import 'package:proport_app/services/portfolio_service.dart';
import 'package:proport_app/services/secure_token_store.dart';

class _NoopTokenStore implements SecureTokenStore {
  @override
  Future<void> deleteRefreshToken() async {}

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> writeRefreshToken(String refreshToken) async {}
}

class _TestAuthService extends AuthService {
  _TestAuthService()
    : super(
        apiClient: ApiClient(baseUrl: 'http://localhost:3000'),
        tokenStore: _NoopTokenStore(),
      );

  @override
  AuthUser? get user => AuthUser(
        id: 'u1',
        email: 'student@example.edu',
        firstName: 'Alex',
        lastName: 'Santos',
        school: 'University of Engineering',
        program: 'Computer Science',
        yearLevel: '4th Year',
        status: 'active',
        emailVerifiedAt: DateTime(2026, 1, 1),
      );
}

class _TestDocumentService extends DocumentService {
  _TestDocumentService() : super(authService: _TestAuthService());

  int previewCalls = 0;
  int uploadCalls = 0;
  PickedDocument? lastUploadedFile;
  List<PickedDocument>? lastUploadedFiles;

  static const _testCategories = [
    DocumentCategory(
      key: 'certificates',
      name: 'Certificates',
      folders: [
        DocumentFolder(key: 'trainings', name: 'Trainings'),
        DocumentFolder(key: 'seminars', name: 'Seminars'),
      ],
    ),
    DocumentCategory(
      key: 'curriculum-vitae',
      name: 'Curriculum Vitae',
      folders: [
        DocumentFolder(key: 'curriculum-vitae', name: 'Curriculum Vitae'),
      ],
    ),
  ];

  @override
  List<DocumentCategory> get categories => _testCategories;

  @override
  bool get hasLoadedCategories => true;

  @override
  bool get hasLoadedDocuments => true;

  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => null;

  @override
  Future<void> load({bool force = false}) async {}

  @override
  DocumentSummary get summary => const DocumentSummary(
        totalCount: 1,
        categoryCounts: {'certificates': 1},
        folderCounts: {'certificates/trainings': 1},
      );

  @override
  List<DocumentRecord> get documents => [
        DocumentRecord(
          id: 'd1',
          categoryKey: 'certificates',
          folderKey: 'trainings',
          title: 'Certificate One',
          documentDate: DateTime(2026, 1, 1),
          originalFileName: 'cert1.pdf',
          mimeType: 'application/pdf',
          fileKind: 'pdf',
          extension: 'pdf',
          sizeBytes: 1024,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      ];

  @override
  Future<DocumentOcrResult> previewOcr(dynamic fileOrFiles) async {
    previewCalls++;
    return DocumentOcrResult(
      status: DocumentOcrStatus.ready,
      rawText: 'Certificate of Attendance Test',
      metadataSuggestions: DocumentMetadataSuggestions(
        categoryKey: 'certificates',
        folderKey: 'seminars',
        title: 'Seminar Certificate',
        documentDate: DateTime(2026, 9, 20),
        confidence: 'high',
      ),
    );
  }

  @override
  Future<DocumentRecord> upload({
    PickedDocument? file,
    List<PickedDocument>? files,
    required String categoryKey,
    required String folderKey,
    required String title,
    required DateTime documentDate,
    String? description,
    String? reflection,
  }) async {
    uploadCalls++;
    lastUploadedFile = file;
    lastUploadedFiles = files;
    final primary = file ?? files?.first;
    return DocumentRecord(
      id: 'doc_$uploadCalls',
      categoryKey: categoryKey,
      folderKey: folderKey,
      title: title,
      documentDate: documentDate,
      description: description,
      reflection: reflection,
      originalFileName: primary?.name ?? 'document.pdf',
      mimeType: primary?.mimeType ?? 'application/pdf',
      fileKind: primary?.mimeType == 'application/pdf' ? 'pdf' : 'image',
      extension: primary?.name.split('.').last ?? 'pdf',
      sizeBytes: primary?.sizeBytes ?? 1024,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      attachments: files != null && files.length > 1
          ? files
              .asMap()
              .entries
              .map(
                (e) => DocumentAttachmentRecord(
                  id: 'att_${e.key}',
                  originalFileName: e.value.name,
                  mimeType: e.value.mimeType,
                  fileKind: 'image',
                  extension: 'jpg',
                  sizeBytes: e.value.sizeBytes,
                  order: e.key,
                ),
              )
              .toList()
          : null,
    );
  }
}

class _TestMockPicker implements DocumentPicker {
  _TestMockPicker({this.cameraResult, this.documentsResult});

  PickedDocument? cameraResult;
  List<PickedDocument>? documentsResult;
  int cameraCalls = 0;
  int documentsCalls = 0;

  @override
  Future<PickedDocument?> pickDocument() async {
    documentsCalls++;
    return documentsResult?.firstOrNull;
  }

  @override
  Future<List<PickedDocument>?> pickDocuments({bool allowMultiple = true}) async {
    documentsCalls++;
    return documentsResult;
  }

  @override
  Future<PickedDocument?> pickFromCamera() async {
    cameraCalls++;
    return cameraResult;
  }
}

class _TestPortfolioExporter implements PortfolioExporter {
  int shareCalls = 0;
  int generateCalls = 0;
  ExportFormat? lastFormat;

  @override
  Future<PortfolioExportFile> generate(
    PortfolioExportContent content,
    ExportFormat format,
  ) async {
    generateCalls++;
    lastFormat = format;
    return PortfolioExportFile(
      path: '/tmp/test_portfolio.pdf',
      name: 'Alex_Santos_Portfolio.pdf',
      format: format,
      sizeBytes: 2048,
    );
  }

  @override
  Future<void> share(PortfolioExportFile file, Rect origin) async {
    shareCalls++;
  }
}

Widget _wrapMain({
  required DocumentService documentService,
  required AuthService authService,
  required DocumentPicker filePicker,
}) {
  return AuthScope(
    authService: authService,
    child: DocumentScope(
      documentService: documentService,
      child: PortfolioScope(
        portfolioService: PortfolioService(
          authService: authService,
        ),
        child: MaterialApp(
          home: MainScreen(filePicker: filePicker),
        ),
      ),
    ),
  );
}

PickedDocument _makeDoc(String name, {String mime = 'application/pdf', int size = 1024}) {
  return PickedDocument(
    name: name,
    mimeType: mime,
    bytes: Uint8List.fromList(List.filled(size, 1)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Center (+) Quick-Action Menu UX', () {
    testWidgets('tap (+) opens Camera and File Upload; second tap closes them', (
      tester,
    ) async {
      final auth = _TestAuthService();
      final docs = _TestDocumentService();
      final picker = _TestMockPicker();

      await tester.pumpWidget(
        _wrapMain(documentService: docs, authService: auth, filePicker: picker),
      );
      await tester.pumpAndSettle();

      // Initially, quick-action buttons are not visible
      expect(find.text('Camera'), findsNothing);
      expect(find.text('File Upload'), findsNothing);

      // Tap center (+) button
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      // Now quick actions are visible
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('File Upload'), findsOneWidget);

      // Tap center (+) button again to close
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Camera'), findsNothing);
      expect(find.text('File Upload'), findsNothing);
    });

    testWidgets('tapping scrim closes quick-action menu', (tester) async {
      final auth = _TestAuthService();
      final docs = _TestDocumentService();
      final picker = _TestMockPicker();

      await tester.pumpWidget(
        _wrapMain(documentService: docs, authService: auth, filePicker: picker),
      );
      await tester.pumpAndSettle();

      // Open menu
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Camera'), findsOneWidget);

      // Tap on top area of screen (scrim)
      await tester.tapAt(const Offset(100, 100));
      await tester.pumpAndSettle();

      expect(find.text('Camera'), findsNothing);
      expect(find.text('File Upload'), findsNothing);
    });

    testWidgets('tapping another bottom nav tab closes quick-action menu and changes tab', (
      tester,
    ) async {
      final auth = _TestAuthService();
      final docs = _TestDocumentService();
      final picker = _TestMockPicker();

      await tester.pumpWidget(
        _wrapMain(documentService: docs, authService: auth, filePicker: picker),
      );
      await tester.pumpAndSettle();

      // Open menu
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Camera'), findsOneWidget);

      // Tap 'Files' tab
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      // Menu closed, Files page visible
      expect(find.text('Camera'), findsNothing);
      expect(find.text('File Upload'), findsNothing);
    });

    testWidgets('Android back closes quick-action menu first rather than leaving screen', (
      tester,
    ) async {
      final auth = _TestAuthService();
      final docs = _TestDocumentService();
      final picker = _TestMockPicker();

      await tester.pumpWidget(
        _wrapMain(documentService: docs, authService: auth, filePicker: picker),
      );
      await tester.pumpAndSettle();

      // Open menu
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Camera'), findsOneWidget);

      // Simulate Android back gesture/press
      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pumpAndSettle();

      // Menu closed, MainScreen still present
      expect(find.text('Camera'), findsNothing);
      expect(find.byType(MainScreen), findsOneWidget);
    });
  });

  group('Camera and File Upload Actions from Quick-Action Menu', () {
    testWidgets('Camera action invokes picker and routes to AddFileScreen with photo', (
      tester,
    ) async {
      final photo = _makeDoc('scan_doc.jpg', mime: 'image/jpeg');
      final picker = _TestMockPicker(cameraResult: photo);
      final auth = _TestAuthService();
      final docs = _TestDocumentService();

      await tester.pumpWidget(
        _wrapMain(documentService: docs, authService: auth, filePicker: picker),
      );
      await tester.pumpAndSettle();

      // Open menu and tap Camera
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Camera'));
      await tester.pumpAndSettle();

      expect(picker.cameraCalls, 1);
      expect(find.byType(AddFileScreen), findsOneWidget);
      expect(find.text('scan_doc.jpg'), findsOneWidget);
      expect(docs.previewCalls, 1);
    });

    testWidgets('Camera cancellation returns cleanly without creating document or leaving menu open', (
      tester,
    ) async {
      final picker = _TestMockPicker(cameraResult: null);
      final auth = _TestAuthService();
      final docs = _TestDocumentService();

      await tester.pumpWidget(
        _wrapMain(documentService: docs, authService: auth, filePicker: picker),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Camera'));
      await tester.pumpAndSettle();

      expect(picker.cameraCalls, 1);
      expect(find.byType(AddFileScreen), findsNothing);
      expect(find.text('Camera'), findsNothing);
      expect(find.text('File Upload'), findsNothing);
    });

    testWidgets('File Upload with 1 file routes to single-document flow in AddFileScreen', (
      tester,
    ) async {
      final singleDoc = _makeDoc('diploma.pdf');
      final picker = _TestMockPicker(documentsResult: [singleDoc]);
      final auth = _TestAuthService();
      final docs = _TestDocumentService();

      await tester.pumpWidget(
        _wrapMain(documentService: docs, authService: auth, filePicker: picker),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('File Upload'));
      await tester.pumpAndSettle();

      expect(picker.documentsCalls, 1);
      expect(find.byType(AddFileScreen), findsOneWidget);
      expect(find.text('diploma.pdf'), findsOneWidget);
      expect(docs.previewCalls, 1);
    });

    testWidgets('File Upload with 2-20 independent files routes to BatchReviewScreen', (
      tester,
    ) async {
      final docsList = [
        _makeDoc('cert1.pdf'),
        _makeDoc('resume.pdf'),
        _makeDoc('award.jpg', mime: 'image/jpeg'),
      ];
      final picker = _TestMockPicker(documentsResult: docsList);
      final auth = _TestAuthService();
      final docs = _TestDocumentService();

      await tester.pumpWidget(
        _wrapMain(documentService: docs, authService: auth, filePicker: picker),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('File Upload'));
      await tester.pumpAndSettle();

      expect(picker.documentsCalls, 1);
      expect(find.byType(BatchReviewScreen), findsOneWidget);
      expect(find.textContaining('Processing: 3 Documents'), findsOneWidget);
    });

    testWidgets('File Upload with > 20 files is rejected gracefully with clear message', (
      tester,
    ) async {
      final twentyOneDocs = List.generate(
        21,
        (i) => _makeDoc('doc_$i.pdf'),
      );
      final picker = _TestMockPicker(documentsResult: twentyOneDocs);
      final auth = _TestAuthService();
      final docs = _TestDocumentService();

      await tester.pumpWidget(
        _wrapMain(documentService: docs, authService: auth, filePicker: picker),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('File Upload'));
      await tester.pumpAndSettle();

      expect(picker.documentsCalls, 1);
      expect(find.byType(BatchReviewScreen), findsNothing);
      expect(find.byType(AddFileScreen), findsNothing);
      expect(
        find.textContaining('You can select up to 20 documents. Selected: 21.'),
        findsOneWidget,
      );
    });
  });

  group('AddFileScreen UX & Multi-Page Document Preservation', () {
    testWidgets('normal AddFileScreen has no separate Batch Upload button', (
      tester,
    ) async {
      final docs = _TestDocumentService();
      final picker = _TestMockPicker();

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentScope(
            documentService: docs,
            child: AddFileScreen(filePicker: picker),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Scan Camera'), findsOneWidget);
      expect(find.text('Batch Upload'), findsNothing);
      expect(find.textContaining('Tip: Batch Upload'), findsNothing);
    });

    testWidgets('multi-page document: adding a page via Add Page preserves single logical doc', (
      tester,
    ) async {
      final page1 = _makeDoc('page1.jpg', mime: 'image/jpeg');
      final page2 = _makeDoc('page2.jpg', mime: 'image/jpeg');
      final picker = _TestMockPicker(documentsResult: [page2]);
      final docs = _TestDocumentService();

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentScope(
            documentService: docs,
            child: AddFileScreen(
              filePicker: picker,
              initialFiles: [page1],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Page 1 is present, Add Page button is shown
      expect(find.text('Document Pages (1)'), findsOneWidget);
      expect(find.text('Add Page (1/10)'), findsOneWidget);

      // Tap Add Page
      await tester.tap(find.text('Add Page (1/10)'));
      await tester.pumpAndSettle();

      // Now 2 pages in one document
      expect(find.text('Document Pages (2)'), findsOneWidget);
      expect(find.text('Page 1'), findsOneWidget);
      expect(find.text('Page 2'), findsOneWidget);

      // Suggested fields from previewOcr are already present, tap Add File
      await tester.ensureVisible(find.text('Add File'));
      await tester.tap(find.text('Add File'));
      await tester.pumpAndSettle();

      // Upload called with both files belonging to one document
      expect(docs.uploadCalls, 1);
      expect(docs.lastUploadedFiles?.length, 2);
      expect(docs.lastUploadedFiles?[0].name, 'page1.jpg');
      expect(docs.lastUploadedFiles?[1].name, 'page2.jpg');
    });
  });

  group('PortfolioExportScreen Navigation to Dashboard', () {
    testWidgets('Back to Dashboard returns to existing MainScreen without duplicating', (
      tester,
    ) async {
      final auth = _TestAuthService();
      final docs = _TestDocumentService();
      final picker = _TestMockPicker();
      final exporter = _TestPortfolioExporter();

      final portfolioInfo = const PortfolioInfo(
        fullName: 'Alex Santos',
        yearAndSection: '4BSIT-1',
        schedule: 'Monday 8:00 AM - 10:00 AM',
        instructorName: 'Professor Example',
        course: 'BSIT',
        courseCode: 'IT101',
        semesterAndYear: '2nd Semester, A.Y. 2025-2026',
      );

      // Pump app with MainScreen at root
      await tester.pumpWidget(
        MaterialApp(
          routes: {
            MainScreen.routeName: (_) => MainScreen(filePicker: picker),
          },
          home: AuthScope(
            authService: auth,
            child: DocumentScope(
              documentService: docs,
              child: PortfolioScope(
                portfolioService: PortfolioService(
                  authService: auth,
                ),
                exporter: exporter,
                child: MainScreen(filePicker: picker),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Push PortfolioExportScreen on top of MainScreen
      final BuildContext mainContext = tester.element(find.byType(MainScreen));
      Navigator.push(
        mainContext,
        MaterialPageRoute(
          builder: (_) => AuthScope(
            authService: auth,
            child: DocumentScope(
              documentService: docs,
              child: PortfolioScope(
                portfolioService: PortfolioService(
                  authService: auth,
                ),
                exporter: exporter,
                child: PortfolioExportScreen(
                  portfolioInfo: portfolioInfo,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PortfolioExportScreen), findsOneWidget);

      // Tap Export Portfolio
      await tester.ensureVisible(find.text('Export Portfolio').last);
      await tester.tap(find.text('Export Portfolio').last);
      await tester.pumpAndSettle();

      expect(find.text('Portfolio file created'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Preview Portfolio'), findsOneWidget);
      expect(find.text('Back to Dashboard'), findsOneWidget);

      // Tap Back to Dashboard
      await tester.ensureVisible(find.text('Back to Dashboard'));
      await tester.tap(find.text('Back to Dashboard'));
      await tester.pumpAndSettle();

      // PortfolioExportScreen is gone, MainScreen is the active screen
      expect(find.byType(PortfolioExportScreen), findsNothing);
      expect(find.byType(MainScreen), findsOneWidget);
    });

    testWidgets('Share and Preview actions remain available and functional', (
      tester,
    ) async {
      final auth = _TestAuthService();
      final docs = _TestDocumentService();
      final exporter = _TestPortfolioExporter();

      final portfolioInfo = const PortfolioInfo(
        fullName: 'Alex Santos',
        yearAndSection: '4BSIT-1',
        schedule: 'Monday 8:00 AM - 10:00 AM',
        instructorName: 'Professor Example',
        course: 'BSIT',
        courseCode: 'IT101',
        semesterAndYear: '2nd Semester, A.Y. 2025-2026',
      );

      await tester.pumpWidget(
        AuthScope(
          authService: auth,
          child: DocumentScope(
            documentService: docs,
            child: PortfolioScope(
              portfolioService: PortfolioService(
                authService: auth,
              ),
              exporter: exporter,
              child: MaterialApp(
                home: PortfolioExportScreen(
                  portfolioInfo: portfolioInfo,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Export Portfolio').last);
      await tester.tap(find.text('Export Portfolio').last);
      await tester.pumpAndSettle();

      // Test Share
      await tester.ensureVisible(find.text('Share'));
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(exporter.shareCalls, 1);

      // Test Preview Portfolio
      await tester.ensureVisible(find.text('Preview Portfolio'));
      await tester.tap(find.text('Preview Portfolio'));
      await tester.pumpAndSettle();
      expect(find.text('Portfolio Preview'), findsOneWidget);
    });
  });
}
