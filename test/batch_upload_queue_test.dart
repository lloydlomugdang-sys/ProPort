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
    AppOcrCoordinator? coordinator,
  }) : super(
          authService: _NoopAuthService(),
          ocrCoordinator: coordinator,
        );

  final int uploadDelayMs;
  final int ocrDelayMs;
  final int failUploadAtIndex;
  final int failOcrAtIndex;
  final bool ocrThrows503;

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

    final docId = 'doc_${DateTime.now().microsecondsSinceEpoch}_$uploadCallCount';
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

PickedDocument _makeDoc(String name, {String? path, Uint8List? bytes, int? sizeBytes}) {
  return PickedDocument(
    name: name,
    mimeType: name.endsWith('.pdf') ? 'application/pdf' : 'image/jpeg',
    path: path,
    bytes: bytes ?? (path == null ? Uint8List.fromList([1, 2, 3, 4]) : null),
    sizeBytes: sizeBytes,
  );
}

void main() {
  group('BatchUploadQueue & AppOcrCoordinator Reliability', () {
    test('accepts up to 20 documents in a batch and initializes all to queued', () {
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
      expect(queue.items.every((item) => item.status == BatchItemStatus.queued), isTrue);
      expect(queue.items.every((item) => item.isValidForUpload), isTrue);
      expect(queue.validToSaveCount, 20);
    });

    test('strictly rejects batches larger than 20 documents with ArgumentError', () {
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
    });

    test('lazy file loading: PickedDocument sizeBytes does not read file bytes, readBytes() reads lazily, releaseBytes() clears memory', () async {
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
    });

    test('enforces bounded upload concurrency with at most 2 concurrent uploads', () async {
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
    });

    test('enforces global app-level OCR serialization: exactly 1 active OCR extraction at any time', () async {
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
    });

    test('cross-caller serialization: batch OCR and standalone extractText share AppOcrCoordinator with maxObservedConcurrent == 1', () async {
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
    });

    test('failure isolation: upload failure in one document does not fail the rest of the batch', () async {
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
    });

    test('OCR failure preserves documentId and retry re-runs OCR without re-uploading (zero duplicate documents)', () async {
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
    });

    test('HTTP 503 OCR_BUSY sets user-friendly recovery message and preserves documentId', () async {
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
    });

    test('file read error / inaccessible file path fails gracefully without crashing the batch', () async {
      final service = _FakeDocumentService();
      final queue = BatchUploadQueue(documentService: service);

      final badDoc = _makeDoc('missing.pdf', path: '/non/existent/path/missing.pdf');
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
    });

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

    test('saveAllValid processes 10 documents and completes all successfully', () async {
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
    });
  });
}
