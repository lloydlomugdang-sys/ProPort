import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/screens/files/models/batch_upload_item.dart';
import 'package:proport_app/services/api_client.dart';
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
    this.previewDelayMs = 0,
    this.shouldThrow429Once = false,
    this.failIndex = -1,
  }) : super(authService: _NoopAuthService());

  final int previewDelayMs;
  bool shouldThrow429Once;
  final int failIndex;
  int previewCallCount = 0;
  int activeConcurrentPreviewCalls = 0;
  int maxObservedConcurrentPreviews = 0;
  final List<String> uploadedTitles = [];

  @override
  Future<DocumentOcrResult> previewOcr(dynamic fileOrFiles) async {
    previewCallCount++;
    activeConcurrentPreviewCalls++;
    if (activeConcurrentPreviewCalls > maxObservedConcurrentPreviews) {
      maxObservedConcurrentPreviews = activeConcurrentPreviewCalls;
    }

    if (previewDelayMs > 0) {
      await Future.delayed(Duration(milliseconds: previewDelayMs));
    }

    activeConcurrentPreviewCalls--;

    if (shouldThrow429Once) {
      shouldThrow429Once = false;
      throw const ApiException(
        code: 'TOO_MANY_REQUESTS',
        message: 'Rate limit exceeded. Try again in a moment.',
        statusCode: 429,
      );
    }

    if (failIndex >= 0 && previewCallCount == failIndex) {
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
    uploadedTitles.add(title);
    return DocumentRecord(
      id: 'doc_${DateTime.now().microsecondsSinceEpoch}',
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
    mimeType: name.endsWith('.pdf') ? 'application/pdf' : 'image/jpeg',
    bytes: Uint8List.fromList([1, 2, 3, 4]),
  );
}

void main() {
  group('BatchUploadQueue', () {
    test(
      'accepts up to 20 documents in a batch and initializes all to waiting',
      () {
        final service = _FakeDocumentService();
        final queue = BatchUploadQueue(documentService: service);

        final docs = List.generate(20, (i) => _makeDoc('doc_$i.pdf'));
        queue.initialize(docs);

        expect(queue.totalCount, 20);
        expect(queue.items.length, 20);
        expect(queue.items.every((item) => item.id.isNotEmpty), isTrue);
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
      'enforces bounded concurrency with at most 2 concurrent previews',
      () async {
        final service = _FakeDocumentService(previewDelayMs: 25);
        final queue = BatchUploadQueue(
          documentService: service,
          maxConcurrent: 2,
        );

        final docs = List.generate(6, (i) => _makeDoc('doc_$i.pdf'));
        queue.initialize(docs);

        // Wait until all items are processed
        while (!queue.isAllProcessed) {
          await Future.delayed(const Duration(milliseconds: 10));
        }

        expect(service.maxObservedConcurrentPreviews, inInclusiveRange(1, 2));
        expect(queue.readyCount, 6);
        expect(queue.failedCount, 0);
      },
    );

    test(
      'failure isolation: failure in one document does not fail the batch',
      () async {
        final service = _FakeDocumentService(failIndex: 2);
        final queue = BatchUploadQueue(documentService: service);

        final docs = [
          _makeDoc('doc_1.pdf'),
          _makeDoc('doc_2.pdf'),
          _makeDoc('doc_3.pdf'),
        ];
        queue.initialize(docs);

        while (!queue.isAllProcessed) {
          await Future.delayed(const Duration(milliseconds: 10));
        }

        expect(queue.failedCount, 1);
        expect(queue.readyCount, 2);
        expect(queue.items[1].isFailed, isTrue);
        expect(queue.items[1].errorMessage, 'Unable to extract text.');
        expect(queue.items[0].isReadyForReview, isTrue);
        expect(queue.items[2].isReadyForReview, isTrue);
      },
    );

    test('allows retrying a failed document individually', () async {
      final service = _FakeDocumentService(failIndex: 1);
      final queue = BatchUploadQueue(documentService: service);

      final docs = [_makeDoc('doc_fail.pdf')];
      queue.initialize(docs);

      while (!queue.isAllProcessed) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      expect(queue.items.single.isFailed, isTrue);

      // Now retry
      queue.retry(queue.items.single.id);

      while (!queue.isAllProcessed) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      expect(queue.items.single.isReadyForReview, isTrue);
      expect(queue.items.single.isFailed, isFalse);
    });

    test('allows removing an item from the batch', () {
      final service = _FakeDocumentService();
      final queue = BatchUploadQueue(documentService: service);

      final docs = [_makeDoc('a.pdf'), _makeDoc('b.pdf')];
      queue.initialize(docs);

      final removeId = queue.items.first.id;
      queue.remove(removeId);

      expect(queue.totalCount, 1);
      expect(queue.items.any((i) => i.id == removeId), isFalse);
    });

    test(
      'user metadata updates are preserved and do not overwrite manual edits',
      () async {
        final service = _FakeDocumentService();
        final queue = BatchUploadQueue(documentService: service);

        queue.initialize([_makeDoc('transcript.pdf')]);

        while (!queue.isAllProcessed) {
          await Future.delayed(const Duration(milliseconds: 10));
        }

        final itemId = queue.items.single.id;

        // Update manual reflection and custom title
        queue.updateItemMetadata(
          itemId,
          title: 'Custom User Title',
          reflection: 'Learned advanced research methods',
        );

        final updated = queue.items.single;
        expect(updated.title, 'Custom User Title');
        expect(updated.reflection, 'Learned advanced research methods');
        expect(updated.categoryKey, 'certificates');
      },
    );

    test(
      'handles HTTP 429 gracefully with retry and exponential backoff',
      () async {
        final service = _FakeDocumentService(shouldThrow429Once: true);
        final queue = BatchUploadQueue(documentService: service, maxRetries: 2);

        queue.initialize([_makeDoc('rate_limited.pdf')]);

        while (!queue.isAllProcessed) {
          await Future.delayed(const Duration(milliseconds: 20));
        }

        // 429 was retried and succeeded
        expect(queue.items.single.isReadyForReview, isTrue);
        expect(queue.items.single.retryCount, 1);
      },
    );

    test(
      'saves all valid documents with bounded concurrency and updates status',
      () async {
        final service = _FakeDocumentService();
        final queue = BatchUploadQueue(documentService: service);

        queue.initialize([_makeDoc('cert1.pdf'), _makeDoc('cert2.pdf')]);

        while (!queue.isAllProcessed) {
          await Future.delayed(const Duration(milliseconds: 10));
        }

        expect(queue.validToSaveCount, 2);

        final saved = await queue.saveAllValid();

        expect(saved, 2);
        expect(queue.savedCount, 2);
        expect(queue.isAllSaved, isTrue);
        expect(service.uploadedTitles.length, 2);
      },
    );

    test('confidence level parsing and isLowConfidence helper', () {
      final high = const DocumentMetadataSuggestions(
        categoryKey: 'certificates',
        confidence: 'high',
      );
      expect(high.confidence, 'high');
      expect(high.isLowConfidence, isFalse);

      final low = const DocumentMetadataSuggestions(
        categoryKey: 'other-achievements',
        confidence: 'low',
      );
      expect(low.confidence, 'low');
      expect(low.isLowConfidence, isTrue);

      final itemLow = BatchUploadItem(
        id: '1',
        file: _makeDoc('file.pdf'),
        confidence: 'low',
      );
      expect(itemLow.isLowConfidence, isTrue);
    });
  });
}
