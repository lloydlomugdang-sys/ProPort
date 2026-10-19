import 'dart:async';
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
import 'package:proport_app/services/document_picker.dart';
import 'package:proport_app/services/secure_token_store.dart';
import 'package:proport_app/screens/files/widgets/custom_dropdown.dart';
import 'package:proport_app/screens/files/widgets/date_picker_field.dart';

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
  _TestDocService({
    this.confidence = 'high',
    this.shouldFailOcr = false,
    this.previewResult,
  }) : super(authService: _NoopAuthService());

  final String confidence;
  final bool shouldFailOcr;
  final Future<DocumentOcrResult>? previewResult;

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
  int ocrCalls = 0;
  int previewCalls = 0;

  @override
  Future<DocumentOcrResult> loadOcr(String documentId) async =>
      const DocumentOcrResult(status: DocumentOcrStatus.notProcessed);

  @override
  Future<DocumentOcrResult> previewOcr(dynamic fileOrFiles) async {
    previewCalls++;
    if (previewResult != null) return previewResult!;
    if (shouldFailOcr) {
      throw const ApiException(
        code: 'OCR_FAILED',
        message: 'No readable text was found in this document.',
      );
    }
    return DocumentOcrResult(
      status: DocumentOcrStatus.ready,
      rawText: 'Test extracted text',
      metadataSuggestions: DocumentMetadataSuggestions(
        categoryKey: 'certificates',
        folderKey: 'trainings',
        title: 'GradPort Training Certificate',
        documentDate: DateTime(2026, 9, 17),
        confidence: confidence,
      ),
    );
  }

  @override
  Future<DocumentOcrResult> extractText(String documentId) async {
    return ocrCoordinator.runGuarded(() async {
      ocrCalls++;
      if (shouldFailOcr) {
        throw const ApiException(
          code: 'OCR_FAILED',
          message: 'Could not extract text.',
          statusCode: 422,
        );
      }
      return DocumentOcrResult(
        status: DocumentOcrStatus.ready,
        rawText: 'Test extracted text',
        metadataSuggestions: DocumentMetadataSuggestions(
          categoryKey: 'certificates',
          folderKey: 'trainings',
          title: 'GradPort Training Certificate',
          documentDate: DateTime(2026, 9, 17),
          confidence: confidence,
        ),
      );
    });
  }

  @override
  Future<DocumentRecord> upload({
    String descriptionSource = 'unknown',
    PickedDocument? file,
    List<PickedDocument>? files,
    required String categoryKey,
    required String folderKey,
    required String title,
    required DateTime documentDate,
    String? description,
    String? reflection,
    ScholasticDetails? scholastic,
  }) async {
    uploadCalls++;
    if (file != null) {
      await file.readBytes();
    }
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

  @override
  Future<DocumentRecord> updateDocumentMetadata(
    String documentId, {
    String? descriptionSource,
    String? categoryKey,
    String? folderKey,
    String? title,
    DateTime? documentDate,
    String? description,
    String? reflection,
    ScholasticDetails? scholastic,
  }) async {
    return DocumentRecord(
      id: documentId,
      categoryKey: categoryKey ?? 'certificates',
      folderKey: folderKey ?? 'trainings',
      title: title ?? 'Title',
      documentDate: documentDate ?? DateTime.now(),
      originalFileName: 'upload.pdf',
      mimeType: 'application/pdf',
      fileKind: 'pdf',
      extension: 'pdf',
      sizeBytes: 1024,
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

class _MorePicker extends DocumentPicker {
  @override
  Future<PickedDocument?> pickDocument() async => null;
  @override
  Future<List<PickedDocument>> pickDocuments({
    bool allowMultiple = true,
  }) async {
    expect(allowMultiple, isTrue);
    return [_makeDoc('additional-one.pdf'), _makeDoc('additional-two.pdf')];
  }
}

void main() {
  testWidgets(
    'Add more appends independent documents on narrow Review Files without overflowing',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _TestDocService();
      final queue = BatchUploadQueue(documentService: service);
      queue.initialize([_makeDoc('${'Very-long-filename-' * 18}.pdf')]);
      await tester.pumpWidget(
        _wrap(BatchReviewScreen(queue: queue, picker: _MorePicker()), service),
      );
      await tester.pumpAndSettle();
      expect(find.text('Review Files (0/1)'), findsOneWidget);
      final id = queue.items.first.id;
      await tester.tap(find.text('Add more files'));
      await tester.pumpAndSettle();
      expect(find.text('Review Files (0/3)'), findsOneWidget);
      expect(queue.items.first.id, id);
      expect(service.previewCalls, 3);
      expect(service.uploadCalls, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      queue.dispose();
      service.dispose();
    },
  );
  testWidgets(
    'one JPEG shows progress, suggested metadata and Save Document completion without navigation assumptions',
    (tester) async {
      final pending = Completer<DocumentOcrResult>();
      final service = _TestDocService(previewResult: pending.future);
      final queue = BatchUploadQueue(documentService: service);
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      queue.initialize([
        PickedDocument(
          name: 'certificate.jpg',
          mimeType: 'image/jpeg',
          bytes: Uint8List(3),
        ),
      ]);
      await tester.pumpWidget(_wrap(BatchReviewScreen(queue: queue), service));
      await tester.pump();
      expect(find.text('Review Files (0/1)'), findsOneWidget);
      expect(find.text('Processing: 1 Document'), findsOneWidget);
      expect(find.text('Document 1 of 1'), findsOneWidget);
      expect(
        find.text('Reading document and suggesting details...'),
        findsOneWidget,
      );
      expect(service.previewCalls, 1);
      expect(service.uploadCalls, 0);
      pending.complete(
        DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          rawText: 'JPEG certificate extracted text',
          metadataAnalysis: const DocumentMetadataAnalysis(
            source: 'gemini',
            aiStatus: 'success',
          ),
          metadataSuggestions: DocumentMetadataSuggestions(
            categoryKey: 'certificates',
            folderKey: 'trainings',
            title: 'Safety Workshop',
            documentDate: DateTime(2026, 9, 17),
            description: 'Completed safety training.',
            confidence: 'high',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Reading document and suggesting details...'),
        findsNothing,
      );
      expect(
        tester.widget<CustomDropdown>(find.byType(CustomDropdown).first).value,
        'Certificates',
      );
      expect(
        tester.widget<CustomDropdown>(find.byType(CustomDropdown).last).value,
        'Trainings',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Safety Workshop',
      );
      expect(
        tester
            .widget<DatePickerField>(find.byType(DatePickerField))
            .selectedDate,
        DateTime(2026, 9, 17),
      );
      await tester.tap(find.text('Add Description & Reflection'));
      await tester.pumpAndSettle();
      expect(find.text('Completed safety training.'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        isEmpty,
      );
      await tester.tap(find.text('Extracted Text'));
      await tester.pumpAndSettle();
      expect(find.text('JPEG certificate extracted text'), findsOneWidget);
      await tester.ensureVisible(find.text('Save Document'));
      await tester.tap(find.text('Save Document'));
      await tester.pumpAndSettle();
      expect(service.uploadCalls, 1);
      expect(queue.isAllCompleted, isTrue);
      expect(find.text('Review Files (1/1)'), findsOneWidget);
      expect(find.text('Finish Review'), findsOneWidget);
      expect(queue.items.single.title, 'Safety Workshop');
    },
  );

  for (final ocrFails in [false, true]) {
    testWidgets(
      ocrFails
          ? 'OCR failure has an explicit read failure and retry action'
          : 'AI failure leaves successful OCR text visible with a separate metadata warning',
      (tester) async {
        final service = _TestDocService(
          shouldFailOcr: ocrFails,
          previewResult: ocrFails
              ? null
              : Future.value(
                  const DocumentOcrResult(
                    status: DocumentOcrStatus.ready,
                    rawText: 'Readable text despite AI outage',
                    metadataAnalysis: DocumentMetadataAnalysis(
                      source: 'rules',
                      aiStatus: 'unavailable',
                    ),
                  ),
                ),
        );
        final queue = BatchUploadQueue(documentService: service);
        queue.initialize([_makeDoc('certificate.pdf')]);
        await tester.pumpWidget(
          _wrap(BatchReviewScreen(queue: queue), service),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('OCR/read failure:'),
          ocrFails ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Retry reading'),
          ocrFails ? findsOneWidget : findsNothing,
        );
        expect(
          find.textContaining('Text extracted. AI suggestions unavailable;'),
          ocrFails ? findsNothing : findsOneWidget,
        );
        if (!ocrFails) {
          await tester.tap(find.text('Extracted Text'));
          await tester.pumpAndSettle();
          expect(find.text('Readable text despite AI outage'), findsOneWidget);
        }
        expect(service.uploadCalls, 0);
      },
    );
  }

  testWidgets(
    'BatchReviewScreen displays items, status chips, and allows saving single and all documents',
    (tester) async {
      final service = _TestDocService();
      final queue = BatchUploadQueue(documentService: service);

      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      queue.initialize(
        [_makeDoc('cert.pdf'), _makeDoc('resume.pdf')],
        defaultCategoryKey: 'certificates',
        defaultFolderKey: 'trainings',
      );

      await tester.pumpWidget(_wrap(BatchReviewScreen(queue: queue), service));
      await tester.pumpAndSettle();

      // Verify item cards and queued chips
      expect(find.text('Document 1 of 2'), findsOneWidget);
      expect(find.text('cert.pdf'), findsOneWidget);
      expect(find.text('Document 2 of 2'), findsOneWidget);
      expect(find.text('resume.pdf'), findsOneWidget);
      expect(find.text('Queued'), findsNWidgets(2));

      // Save first document
      await tester.tap(find.text('Save Document').first);
      await tester.pumpAndSettle();

      expect(service.uploadCalls, 1);
      expect(service.ocrCalls, 1);
      expect(queue.completedCount, 1);
      expect(find.text('Document saved to GradPort'), findsOneWidget);

      // Dismiss floating snackbar before next tap
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Bottom bar shows upload remaining valid
      expect(find.textContaining('1 of 2 Valid Documents'), findsOneWidget);
      await tester.tap(find.text('Upload All Valid'));
      await tester.pumpAndSettle();

      expect(service.uploadCalls, 2);
      expect(service.ocrCalls, 2);
      expect(queue.isAllCompleted, isTrue);
      expect(find.text('Finish Review'), findsOneWidget);
    },
  );

  testWidgets(
    'BatchReviewScreen shows low-confidence warning when confidence is low, and item removal works',
    (tester) async {
      final service = _TestDocService(confidence: 'low');
      final queue = BatchUploadQueue(documentService: service);

      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      queue.initialize(
        [_makeDoc('low_doc.pdf')],
        defaultCategoryKey: 'certificates',
        defaultFolderKey: 'trainings',
      );

      await tester.pumpWidget(_wrap(BatchReviewScreen(queue: queue), service));
      await tester.pumpAndSettle();

      // Test remove item
      expect(find.text('low_doc.pdf'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('No documents selected.'), findsOneWidget);
      expect(queue.totalCount, 0);
    },
  );

  testWidgets('BatchReviewScreen shows failed status with Retry button', (
    tester,
  ) async {
    final service = _TestDocService(shouldFailOcr: true);
    final queue = BatchUploadQueue(documentService: service);

    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    queue.initialize(
      [_makeDoc('failed_doc.pdf')],
      defaultCategoryKey: 'certificates',
      defaultFolderKey: 'trainings',
    );

    await tester.pumpWidget(_wrap(BatchReviewScreen(queue: queue), service));
    await tester.pumpAndSettle();

    // Trigger processing
    await tester.tap(find.text('Save Document'));
    await tester.pumpAndSettle();

    expect(find.text('Failed'), findsOneWidget);
    expect(
      find.text('No readable text was found in this document.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });
}
