import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/screens/files/models/batch_upload_item.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/app_ocr_coordinator.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/batch_upload_queue.dart';
import 'package:proport_app/services/document_models.dart';
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

class _FakeDocumentService extends DocumentService {
  _FakeDocumentService({
    this.uploadDelayMs = 0,
    this.ocrDelayMs = 0,
    this.failUploadAtIndex = -1,
    this.failOcrAtIndex = -1,
    this.ocrThrows503 = false,
    this.preview,
    AppOcrCoordinator? coordinator,
  }) : super(authService: _NoopAuthService(), ocrCoordinator: coordinator);

  final int uploadDelayMs;
  final int ocrDelayMs;
  final int failUploadAtIndex;
  final int failOcrAtIndex;
  final bool ocrThrows503;
  Future<DocumentOcrResult> Function(PickedDocument)? preview;
  final List<PickedDocument> previewFiles = [];
  final List<PickedDocument?> uploadedFiles = [];
  final List<List<PickedDocument>?> combinedUploads = [];
  DocumentOcrResult persistedOcr = const DocumentOcrResult(
    status: DocumentOcrStatus.notProcessed,
  );
  int loadOcrCalls = 0;

  @override
  Future<DocumentOcrResult> loadOcr(String documentId) async {
    loadOcrCalls++;
    return persistedOcr;
  }

  @override
  Future<DocumentOcrResult> previewOcr(dynamic fileOrFiles) async {
    // A normal queue item must always be one file, never combined pages.
    final file = fileOrFiles as PickedDocument;
    previewFiles.add(file);
    if (preview != null) return preview!(file);
    return DocumentOcrResult(
      status: DocumentOcrStatus.ready,
      rawText: 'Extracted text for ${file.name}',
      metadataAnalysis: const DocumentMetadataAnalysis(
        source: 'gemini',
        aiStatus: 'success',
      ),
      metadataSuggestions: DocumentMetadataSuggestions(
        categoryKey: file.name.startsWith('cv')
            ? 'curriculum-vitae'
            : 'certificates',
        folderKey: file.name.startsWith('cv')
            ? 'curriculum-vitae'
            : 'trainings',
        title: 'Suggested ${file.name}',
        documentDate: DateTime(2026, 9, 17),
        description: 'Description for ${file.name}',
        confidence: 'high',
      ),
    );
  }

  int uploadCallCount = 0;
  int activeConcurrentUploads = 0;
  int maxObservedConcurrentUploads = 0;

  int ocrCallCount = 0;
  int activeConcurrentOcr = 0;
  int maxObservedConcurrentOcr = 0;

  final List<String> uploadedTitles = [];
  final List<String> uploadedIds = [];

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
    uploadCallCount++;
    final uploadIndex = uploadCallCount;
    uploadedFiles.add(file);
    combinedUploads.add(files);
    activeConcurrentUploads++;
    if (activeConcurrentUploads > maxObservedConcurrentUploads) {
      maxObservedConcurrentUploads = activeConcurrentUploads;
    }

    if (uploadDelayMs > 0) {
      await Future.delayed(Duration(milliseconds: uploadDelayMs));
    }

    activeConcurrentUploads--;

    if (failUploadAtIndex >= 0 && uploadCallCount == failUploadAtIndex) {
      throw const ApiException(
        code: 'UPLOAD_FAILED',
        message: 'Network error uploading file.',
        statusCode: 500,
      );
    }

    // Read bytes as real upload does
    if (file != null) {
      await file.readBytes();
    }

    final docId = 'doc_$uploadIndex';
    uploadedTitles.add(title);
    uploadedIds.add(docId);

    return DocumentRecord(
      id: docId,
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
  Future<DocumentOcrResult> extractText(String documentId) async {
    return ocrCoordinator.runGuarded(() async {
      ocrCallCount++;
      activeConcurrentOcr++;
      if (activeConcurrentOcr > maxObservedConcurrentOcr) {
        maxObservedConcurrentOcr = activeConcurrentOcr;
      }

      if (ocrDelayMs > 0) {
        await Future.delayed(Duration(milliseconds: ocrDelayMs));
      }

      activeConcurrentOcr--;

      if (ocrThrows503) {
        throw const ApiException(
          code: 'OCR_BUSY',
          message: 'Another OCR job is currently running on this instance.',
          statusCode: 503,
        );
      }

      if (failOcrAtIndex >= 0 && ocrCallCount == failOcrAtIndex) {
        throw const ApiException(
          code: 'OCR_FAILED',
          message: 'Unable to extract text.',
          statusCode: 422,
        );
      }

      return const DocumentOcrResult(
        status: DocumentOcrStatus.ready,
        rawText: 'CERTIFICATE OF COMPLETION\nAwarded to Juan Dela Cruz',
        metadataSuggestions: DocumentMetadataSuggestions(
          categoryKey: 'certificates',
          folderKey: 'trainings',
          title: 'Certificate of Completion',
          confidence: 'high',
        ),
      );
    });
  }

  @override
  Future<DocumentRecord> updateDocumentMetadata(
    String documentId, {
    String? categoryKey,
    String? folderKey,
    String? title,
    DateTime? documentDate,
    String? description,
    String? reflection,
  }) async {
    return DocumentRecord(
      id: documentId,
      categoryKey: categoryKey ?? 'certificates',
      folderKey: folderKey ?? 'trainings',
      title: title ?? 'Updated Document',
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

PickedDocument _makeDoc(
  String name, {
  String? path,
  Uint8List? bytes,
  int? sizeBytes,
}) {
  return PickedDocument(
    name: name,
    mimeType: name.endsWith('.pdf') ? 'application/pdf' : 'image/jpeg',
    path: path,
    bytes: bytes ?? (path == null ? Uint8List.fromList([1, 2, 3, 4]) : null),
    sizeBytes: sizeBytes,
  );
}

void main() {
  group('Unified review preparation', () {
    test(
      'save reuses server-persisted preview OCR instead of running extraction twice',
      () async {
        final service = _FakeDocumentService()
          ..persistedOcr = const DocumentOcrResult(
            status: DocumentOcrStatus.ready,
            rawText: 'Stored OCR text',
          );
        final queue = BatchUploadQueue(documentService: service);
        addTearDown(queue.dispose);
        queue.initialize([_makeDoc('certificate.jpg')]);
        await queue.prepare();
        expect(await queue.saveAllValid(), 1);
        expect(service.previewFiles, hasLength(1));
        expect(service.loadOcrCalls, 1);
        expect(service.ocrCallCount, 0);
        expect(service.uploadCallCount, 1);
      },
    );

    for (final count in [1, 2, 20]) {
      test(
        '$count independent files use the same preview, validation and save processor',
        () async {
          final service = _FakeDocumentService();
          final queue = BatchUploadQueue(documentService: service);
          addTearDown(queue.dispose);
          final files = List.generate(
            count,
            (i) => _makeDoc(i == 1 ? 'cv.jpg' : 'certificate_$i.jpg'),
          );
          queue.initialize(files);
          await queue.prepare();
          await queue
              .prepare(); // Rebuilds cannot start duplicate preview requests.
          expect(service.previewFiles, files);
          expect(service.uploadCallCount, 0);
          expect(
            queue.items.every((i) => i.isValidForUpload && i.isAutoCategorized),
            isTrue,
          );
          expect(queue.items.first.title, 'Suggested certificate_0.jpg');
          expect(queue.items.first.documentDate, DateTime(2026, 9, 17));
          expect(
            queue.items.first.description,
            'Description for certificate_0.jpg',
          );
          expect(
            queue.items.first.rawText,
            'Extracted text for certificate_0.jpg',
          );
          if (count > 1) {
            expect(queue.items[1].categoryKey, 'curriculum-vitae');
            expect(queue.items[1].folderKey, 'curriculum-vitae');
          }
          expect(await queue.saveAllValid(), count);
          expect(service.uploadedFiles, files);
          expect(
            service.combinedUploads.every((files) => files == null),
            isTrue,
          );
          expect(service.ocrCallCount, count);
          expect(
            queue.items.map((item) => item.documentId).toSet(),
            hasLength(count),
          );
          expect(queue.items.first.title, 'Suggested certificate_0.jpg');
          if (count > 1) expect(queue.items[1].categoryKey, 'curriculum-vitae');
          expect(service.ocrCoordinator.maxObservedConcurrent, 1);
        },
      );
    }

    test(
      'AI failure retains successful OCR and rule suggestions, separate from OCR/read failure',
      () async {
        final service = _FakeDocumentService(
          preview: (_) async => const DocumentOcrResult(
            status: DocumentOcrStatus.ready,
            rawText: 'Readable certificate text despite AI outage',
            metadataAnalysis: DocumentMetadataAnalysis(
              source: 'rules',
              aiStatus: 'unavailable',
            ),
            metadataSuggestions: DocumentMetadataSuggestions(
              title: 'Basic certificate',
            ),
          ),
        );
        final queue = BatchUploadQueue(documentService: service);
        addTearDown(queue.dispose);
        queue.initialize([_makeDoc('certificate.jpg')]);
        await queue.prepare();
        expect(
          queue.items.single.rawText,
          'Readable certificate text despite AI outage',
        );
        expect(queue.items.single.title, 'Basic certificate');
        expect(queue.items.single.previewError, isNull);
        expect(
          queue.items.single.previewResult?.metadataAnalysis?.aiStatus,
          'unavailable',
        );
        // Incomplete metadata cannot be saved, even in a one-item queue.
        expect(await queue.saveItem(queue.items.single.id), isFalse);
        expect(service.uploadCallCount, 0);

        service.preview = (_) async => throw const ApiException(
          code: 'OCR_FAILED',
          message: 'No readable text.',
        );
        await queue.prepareItem(queue.items.single.id);
        expect(queue.items.single.previewError, 'No readable text.');
        expect(
          queue.items.single.rawText,
          'Readable certificate text despite AI outage',
        );
      },
    );

    test(
      'late preview and explicit reread preserve all six manually edited fields',
      () async {
        final pending = Completer<DocumentOcrResult>();
        final service = _FakeDocumentService(preview: (_) => pending.future);
        final queue = BatchUploadQueue(documentService: service);
        addTearDown(queue.dispose);
        queue.initialize([_makeDoc('certificate.jpg')]);
        final preparation = queue.prepare();
        expect(queue.items.single.isPreviewing, isTrue);
        final id = queue.items.single.id;
        queue.updateItemMetadata(
          id,
          categoryKey: 'curriculum-vitae',
          folderKey: 'curriculum-vitae',
          title: 'My title',
          documentDate: DateTime(2025, 3, 2),
          description: 'My description',
          reflection: 'My reflection',
        );
        pending.complete(
          const DocumentOcrResult(
            status: DocumentOcrStatus.ready,
            rawText: 'Automatic text',
            metadataSuggestions: DocumentMetadataSuggestions(
              categoryKey: 'certificates',
              folderKey: 'trainings',
              title: 'Automatic title',
              description: 'Automatic description',
            ),
          ),
        );
        await preparation;
        await queue.prepareItem(id);
        await queue.saveAllValid();
        final item = queue.items.single;
        expect(item.categoryKey, 'curriculum-vitae');
        expect(item.folderKey, 'curriculum-vitae');
        expect(item.title, 'My title');
        expect(item.documentDate, DateTime(2025, 3, 2));
        expect(item.description, 'My description');
        expect(item.reflection, 'My reflection');
        expect(item.rawText, 'Automatic text');
        expect(item.isCompleted, isTrue);
        expect(service.uploadedTitles, ['My title']);
      },
    );

    test(
      'Upload All waits for all preview results before saving independent files',
      () async {
        final pending = Completer<DocumentOcrResult>();
        final service = _FakeDocumentService(preview: (_) => pending.future);
        final queue = BatchUploadQueue(documentService: service);
        addTearDown(queue.dispose);
        queue.initialize(
          [_makeDoc('one.jpg'), _makeDoc('two.jpg')],
          defaultCategoryKey: 'certificates',
          defaultFolderKey: 'trainings',
        );
        final preparation = queue.prepare();
        final saving = queue.saveAllValid();
        await Future<void>.delayed(Duration.zero);
        expect(service.uploadCallCount, 0);
        pending.complete(
          const DocumentOcrResult(
            status: DocumentOcrStatus.ready,
            rawText: 'Readable text',
          ),
        );
        await preparation;
        expect(await saving, 2);
        expect(service.previewFiles, hasLength(2));
        expect(service.uploadCallCount, 2);
      },
    );

    test(
      'closing review discards late preview results without persistence',
      () async {
        final pending = Completer<DocumentOcrResult>();
        final service = _FakeDocumentService(preview: (_) => pending.future);
        final queue = BatchUploadQueue(documentService: service);
        queue.initialize([_makeDoc('one.jpg'), _makeDoc('two.jpg')]);
        final preparation = queue.prepare();
        // Let the shared coordinator start the preview, then leave the screen.
        await Future<void>.delayed(Duration.zero);
        queue.dispose();
        pending.complete(
          const DocumentOcrResult(
            status: DocumentOcrStatus.ready,
            rawText: 'Late text',
          ),
        );
        await preparation;
        expect(service.previewFiles, hasLength(1));
        expect(service.uploadCallCount, 0);
        expect(queue.items.first.rawText, isNull);
      },
    );
  });

  group('BatchUploadQueue & AppOcrCoordinator Reliability', () {
    test(
      'accepts up to 20 documents in a batch and initializes all to queued',
      () {
        final service = _FakeDocumentService();
        final queue = BatchUploadQueue(documentService: service);

        final docs = List.generate(20, (i) => _makeDoc('doc_$i.pdf'));
        queue.initialize(
          docs,
          defaultCategoryKey: 'certificates',
          defaultFolderKey: 'trainings',
        );

        expect(queue.totalCount, 20);
        expect(queue.items.length, 20);
        expect(
          queue.items.every((item) => item.status == BatchItemStatus.queued),
          isTrue,
        );
        expect(queue.items.every((item) => item.isValidForUpload), isTrue);
        expect(queue.validToSaveCount, 20);
      },
    );

    test(
      'strictly rejects batches larger than 20 documents with ArgumentError',
      () {
        final service = _FakeDocumentService();
        final queue = BatchUploadQueue(documentService: service);

        final docs = List.generate(21, (i) => _makeDoc('doc_$i.pdf'));
        expect(
          () => queue.initialize(docs),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('You can select up to 20 documents'),
            ),
          ),
        );
      },
    );

    test(
      'lazy file loading: PickedDocument sizeBytes does not read file bytes, readBytes() reads lazily, releaseBytes() clears memory',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('proport_test_');
        final tempFile = File('${tempDir.path}/test_sample.pdf');
        await tempFile.writeAsBytes([1, 2, 3, 4, 5, 6, 7, 8]);

        try {
          final doc = PickedDocument(
            name: 'test_sample.pdf',
            mimeType: 'application/pdf',
            path: tempFile.path,
            sizeBytes: 8,
          );

          // Bytes must NOT be eagerly loaded
          expect(doc.hasBytes, isFalse);
          expect(doc.sizeBytes, 8);

          // Read bytes lazily
          final loaded = await doc.readBytes();
          expect(loaded.length, 8);
          expect(doc.hasBytes, isTrue);

          // Release bytes
          doc.releaseBytes();
          expect(doc.hasBytes, isFalse);
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );

    test(
      'enforces bounded upload concurrency with at most 2 concurrent uploads',
      () async {
        final service = _FakeDocumentService(uploadDelayMs: 30);
        final queue = BatchUploadQueue(
          documentService: service,
          maxConcurrentUploads: 2,
        );

        final docs = List.generate(6, (i) => _makeDoc('doc_$i.pdf'));
        queue.initialize(
          docs,
          defaultCategoryKey: 'certificates',
          defaultFolderKey: 'trainings',
        );

        final future = queue.startProcessing();
        await future;

        expect(service.maxObservedConcurrentUploads, inInclusiveRange(1, 2));
        expect(queue.completedCount, 6);
        expect(queue.failedCount, 0);
      },
    );

    test(
      'enforces global app-level OCR serialization: exactly 1 active OCR extraction at any time',
      () async {
        final service = _FakeDocumentService(ocrDelayMs: 25);
        final queue = BatchUploadQueue(
          documentService: service,
          maxConcurrentUploads: 2,
        );

        final docs = List.generate(4, (i) => _makeDoc('doc_$i.pdf'));
        queue.initialize(
          docs,
          defaultCategoryKey: 'certificates',
          defaultFolderKey: 'trainings',
        );

        await queue.startProcessing();

        expect(service.maxObservedConcurrentOcr, 1);
        expect(service.ocrCoordinator.maxObservedConcurrent, 1);
        expect(queue.completedCount, 4);
      },
    );

    test(
      'cross-caller serialization: batch OCR and standalone extractText share AppOcrCoordinator with maxObservedConcurrent == 1',
      () async {
        final coordinator = AppOcrCoordinator(maxConcurrent: 1);
        final service = _FakeDocumentService(
          ocrDelayMs: 40,
          coordinator: coordinator,
        );
        final queue = BatchUploadQueue(
          documentService: service,
          maxConcurrentUploads: 2,
        );

        final docs = [_makeDoc('doc_batch.pdf')];
        queue.initialize(
          docs,
          defaultCategoryKey: 'certificates',
          defaultFolderKey: 'trainings',
        );

        // Start batch processing (which will run upload then extractText)
        final batchFuture = queue.startProcessing();

        // Slightly delay then start an independent extractText (e.g. from DocumentOcrScreen "Extract Again")
        await Future.delayed(const Duration(milliseconds: 10));
        final externalOcrFuture = service.extractText('doc_external');

        await Future.wait([batchFuture, externalOcrFuture]);

        // Global coordinator must have strictly enforced max 1 active concurrent OCR
        expect(coordinator.maxObservedConcurrent, 1);
        expect(service.maxObservedConcurrentOcr, 1);
        expect(queue.completedCount, 1);
      },
    );

    test(
      'failure isolation: upload failure in one document does not fail the rest of the batch',
      () async {
        final service = _FakeDocumentService(failUploadAtIndex: 2);
        final queue = BatchUploadQueue(documentService: service);

        final docs = [
          _makeDoc('doc_1.pdf'),
          _makeDoc('doc_2.pdf'),
          _makeDoc('doc_3.pdf'),
        ];
        queue.initialize(
          docs,
          defaultCategoryKey: 'certificates',
          defaultFolderKey: 'trainings',
        );

        await queue.startProcessing();

        expect(queue.failedCount, 1);
        expect(queue.completedCount, 2);
        expect(queue.items[1].isFailed, isTrue);
        expect(queue.items[1].errorMessage, 'Network error uploading file.');
        expect(queue.items[0].isCompleted, isTrue);
        expect(queue.items[2].isCompleted, isTrue);
      },
    );

    test(
      'OCR failure preserves documentId and retry re-runs OCR without re-uploading (zero duplicate documents)',
      () async {
        final service = _FakeDocumentService(failOcrAtIndex: 1);
        final queue = BatchUploadQueue(documentService: service);

        final docs = [_makeDoc('doc_ocr_fail.pdf')];
        queue.initialize(
          docs,
          defaultCategoryKey: 'certificates',
          defaultFolderKey: 'trainings',
        );

        await queue.startProcessing();

        expect(queue.items.single.isFailed, isTrue);
        expect(queue.items.single.isUploaded, isTrue);
        final originalDocId = queue.items.single.documentId;
        expect(originalDocId, isNotNull);
        expect(service.uploadCallCount, 1);

        // Now retry the failed OCR item
        queue.retry(queue.items.single.id);
        while (!queue.isAllProcessed) {
          await Future.delayed(const Duration(milliseconds: 10));
        }

        // Verification: upload was NOT called again (zero duplicates created in MongoDB)
        expect(service.uploadCallCount, 1);
        expect(service.ocrCallCount, 2);
        expect(queue.items.single.isCompleted, isTrue);
        expect(queue.items.single.documentId, originalDocId);
      },
    );

    test(
      'HTTP 503 OCR_BUSY sets user-friendly recovery message and preserves documentId',
      () async {
        final service = _FakeDocumentService(ocrThrows503: true);
        final queue = BatchUploadQueue(documentService: service);

        final docs = [_makeDoc('busy_doc.pdf')];
        queue.initialize(
          docs,
          defaultCategoryKey: 'certificates',
          defaultFolderKey: 'trainings',
        );

        await queue.startProcessing();

        final item = queue.items.single;
        expect(item.isFailed, isTrue);
        expect(item.isUploaded, isTrue);
        expect(item.documentId, isNotNull);
        expect(
          item.errorMessage,
          'The server is busy extracting another document. Tap Retry to extract text.',
        );
      },
    );

    test(
      'file read error / inaccessible file path fails gracefully without crashing the batch',
      () async {
        final service = _FakeDocumentService();
        final queue = BatchUploadQueue(documentService: service);

        final badDoc = _makeDoc(
          'missing.pdf',
          path: '/non/existent/path/missing.pdf',
        );
        final goodDoc = _makeDoc('good.pdf');

        queue.initialize(
          [badDoc, goodDoc],
          defaultCategoryKey: 'certificates',
          defaultFolderKey: 'trainings',
        );

        await queue.startProcessing();

        expect(queue.failedCount, 1);
        expect(queue.completedCount, 1);
        expect(
          queue.items[0].errorMessage,
          'The file could not be read from device storage. Please try again.',
        );
        expect(queue.items[1].isCompleted, isTrue);
      },
    );

    test('allows removing a queued item', () {
      final service = _FakeDocumentService();
      final queue = BatchUploadQueue(documentService: service);

      final docs = [_makeDoc('a.pdf'), _makeDoc('b.pdf')];
      queue.initialize(docs);

      final removeId = queue.items.first.id;
      queue.remove(removeId);

      expect(queue.totalCount, 1);
      expect(queue.items.any((i) => i.id == removeId), isFalse);
    });

    test('user metadata updates are preserved', () {
      final service = _FakeDocumentService();
      final queue = BatchUploadQueue(documentService: service);

      queue.initialize([_makeDoc('transcript.pdf')]);

      final itemId = queue.items.single.id;
      queue.updateItemMetadata(
        itemId,
        categoryKey: 'certificates',
        folderKey: 'trainings',
        title: 'Custom User Title',
        reflection: 'Learned advanced research methods',
      );

      final updated = queue.items.single;
      expect(updated.title, 'Custom User Title');
      expect(updated.reflection, 'Learned advanced research methods');
      expect(updated.categoryKey, 'certificates');
      expect(updated.folderKey, 'trainings');
    });

    test(
      'saveAllValid processes 10 documents and completes all successfully',
      () async {
        final service = _FakeDocumentService();
        final queue = BatchUploadQueue(documentService: service);

        final docs = List.generate(10, (i) => _makeDoc('doc_$i.pdf'));
        queue.initialize(
          docs,
          defaultCategoryKey: 'certificates',
          defaultFolderKey: 'trainings',
        );

        expect(queue.validToSaveCount, 10);

        final saved = await queue.saveAllValid();

        expect(saved, 10);
        expect(queue.completedCount, 10);
        expect(queue.isAllCompleted, isTrue);
        expect(service.uploadCallCount, 10);
        expect(service.ocrCallCount, 10);
      },
    );
  });
}
