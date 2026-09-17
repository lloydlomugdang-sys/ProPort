import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/screens/files/batch_review_screen.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/batch_upload_queue.dart';
import 'package:proport_app/services/document_models.dart';
import 'package:proport_app/services/document_scope.dart';
import 'package:proport_app/services/document_service.dart';
import 'package:proport_app/services/secure_token_store.dart';

class _NoopTokenStore implements SecureTokenStore {
  @override
  Future<void> deleteRefreshToken() async {}

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> writeRefreshToken(String refreshToken) async {}
}

class _NoopAuthService extends AuthService {
  _NoopAuthService()
    : super(
        apiClient: ApiClient(baseUrl: 'http://example.test:3000'),
        tokenStore: _NoopTokenStore(),
      );
}

class _TestDocService extends DocumentService {
  _TestDocService({this.confidence = 'high', this.shouldFailPreview = false})
    : super(authService: _NoopAuthService());

  final String confidence;
  final bool shouldFailPreview;

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

  int uploadCalls = 0;

  @override
  Future<DocumentOcrResult> previewOcr(dynamic fileOrFiles) async {
    if (shouldFailPreview) {
      throw const ApiException(
        code: 'OCR_FAILED',
        message: 'Could not extract text.',
        statusCode: 422,
      );
    }
    return DocumentOcrResult(
      status: DocumentOcrStatus.ready,
      rawText: 'Test text',
      metadataSuggestions: DocumentMetadataSuggestions(
        categoryKey: confidence == 'low' ? null : 'certificates',
        folderKey: confidence == 'low' ? null : 'trainings',
        title: 'GradPort Training Certificate',
        documentDate: DateTime(2026, 9, 17),
        confidence: confidence,
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
    return DocumentRecord(
      id: 'doc_saved_$uploadCalls',
      categoryKey: categoryKey,
      folderKey: folderKey,
      title: title,
      documentDate: documentDate,
      description: description,
      reflection: reflection,
      originalFileName: file?.name ?? 'upload.pdf',
      mimeType: file?.mimeType ?? 'application/pdf',
      fileKind: 'pdf',
      extension: 'pdf',
      sizeBytes: file?.sizeBytes ?? 1024,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}

PickedDocument _makeDoc(String name) {
  return PickedDocument(
    name: name,
    mimeType: 'application/pdf',
    bytes: Uint8List.fromList([1, 2, 3]),
  );
}

Widget _wrap(Widget child, DocumentService service) {
  return MaterialApp(
    home: DocumentScope(documentService: service, child: child),
  );
}

void main() {
  testWidgets(
    'BatchReviewScreen displays items, confidence badges, and allows editing & save',
    (tester) async {
      final service = _TestDocService();
      final queue = BatchUploadQueue(documentService: service);

      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      queue.initialize([_makeDoc('cert.pdf'), _makeDoc('resume.pdf')]);

      await tester.pumpWidget(_wrap(BatchReviewScreen(queue: queue), service));
      await tester.pumpAndSettle();

      // Set second item to low confidence to test low confidence UI
      queue.updateItemMetadata(queue.items[1].id, title: 'My Resume');
      await tester.pumpAndSettle();

      // Verify progress banner
      expect(
        find.textContaining('Batch Processing: 2 Documents'),
        findsOneWidget,
      );
      expect(find.textContaining('ready'), findsOneWidget);

      // Verify item cards
      expect(find.text('Document 1 of 2'), findsOneWidget);
      expect(find.text('cert.pdf'), findsOneWidget);
      expect(find.text('Document 2 of 2'), findsOneWidget);
      expect(find.text('resume.pdf'), findsOneWidget);

      // Verify confidence badge
      expect(find.text('High Confidence'), findsWidgets);

      // Save first document
      await tester.tap(find.text('Save Document').first);
      await tester.pumpAndSettle();

      expect(service.uploadCalls, 1);
      expect(queue.savedCount, 1);
      expect(find.text('Document saved to GradPort'), findsOneWidget);

      // Dismiss floating snackbar before next tap
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Bottom bar shows save all
      expect(find.textContaining('1 of 2 Valid Documents'), findsOneWidget);
      await tester.tap(find.text('Save All Valid'));
      await tester.pumpAndSettle();

      expect(service.uploadCalls, 2);
      expect(queue.savedCount, 2);
      expect(queue.isAllSaved, isTrue);
      expect(find.text('Finish Batch'), findsOneWidget);
    },
  );

  testWidgets(
    'BatchReviewScreen shows low-confidence warning, retry on failure, and item removal',
    (tester) async {
      final service = _TestDocService(confidence: 'low');
      final queue = BatchUploadQueue(documentService: service);

      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      queue.initialize([_makeDoc('low_doc.pdf')]);

      await tester.pumpWidget(_wrap(BatchReviewScreen(queue: queue), service));
      await tester.pumpAndSettle();

      // Verify low confidence badge and warning message
      expect(find.text('Low Confidence'), findsOneWidget);
      expect(
        find.textContaining(
          'Low confidence: Please confirm the suggested category and folder.',
        ),
        findsOneWidget,
      );

      // Test remove item
      expect(find.text('low_doc.pdf'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('No documents in this batch.'), findsOneWidget);
      expect(queue.totalCount, 0);
    },
  );

  testWidgets('BatchReviewScreen shows failed status with Retry button', (
    tester,
  ) async {
    final service = _TestDocService(shouldFailPreview: true);
    final queue = BatchUploadQueue(documentService: service);

    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    queue.initialize([_makeDoc('failed_doc.pdf')]);

    await tester.pumpWidget(_wrap(BatchReviewScreen(queue: queue), service));
    await tester.pumpAndSettle();

    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Could not extract text.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
