import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/screens/files/compiled_review_screen.dart';
import 'package:proport_app/screens/files/models/batch_upload_item.dart';
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

class _MockCompiledDocService extends DocumentService {
  _MockCompiledDocService() : super(authService: _NoopAuthService());

  static const _testCategories = [
    DocumentCategory(
      key: 'curriculum-vitae',
      name: 'Curriculum Vitae',
      folders: [
        DocumentFolder(key: 'curriculum-vitae', name: 'Curriculum Vitae'),
      ],
    ),
    DocumentCategory(
      key: 'certificates',
      name: 'Certificates',
      folders: [
        DocumentFolder(key: 'seminars', name: 'Seminars'),
        DocumentFolder(key: 'trainings', name: 'Trainings'),
      ],
    ),
  ];

  @override
  List<DocumentCategory> get categories => _testCategories;

  int splitCallCount = 0;
  int cancelCallCount = 0;
  List<CompiledSplitSegment>? lastSplitSegments;

  @override
  Future<List<DocumentRecord>> splitCompiledDocument({
    required String sessionId,
    required String idempotencyKey,
    required List<CompiledSplitSegment> segments,
  }) async {
    splitCallCount++;
    lastSplitSegments = segments;
    return segments.map<DocumentRecord>((s) {
      return DocumentRecord(
        id: 'split_doc_${s.startPage}',
        categoryKey: s.categoryKey,
        folderKey: s.folderKey,
        title: s.title,
        documentDate: s.documentDate ?? DateTime.now(),
        originalFileName: '${s.title}.pdf',
        mimeType: 'application/pdf',
        fileKind: 'pdf',
        extension: 'pdf',
        sizeBytes: 1024,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }).toList();
  }

  @override
  Future<bool> cancelCompiledSession(String sessionId) async {
    cancelCallCount++;
    return true;
  }
}

class _BatchTestDocService extends DocumentService {
  _BatchTestDocService() : super(authService: _NoopAuthService());

  DocumentMetadataSuggestions? nextSuggestions;
  int updateMetadataCallCount = 0;

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
    return DocumentRecord(
      id: 'doc_${file?.name ?? 'upload.pdf'}',
      categoryKey: categoryKey,
      folderKey: folderKey,
      title: title,
      documentDate: documentDate,
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
    return DocumentOcrResult(
      status: DocumentOcrStatus.ready,
      rawText: 'Recognized text content',
      reviewedText: 'Recognized text content',
      metadataSuggestions: nextSuggestions,
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
    updateMetadataCallCount++;
    return DocumentRecord(
      id: documentId,
      categoryKey: categoryKey ?? 'curriculum-vitae',
      folderKey: folderKey ?? 'curriculum-vitae',
      title: title ?? 'Updated Title',
      documentDate: documentDate ?? DateTime.now(),
      originalFileName: 'doc.pdf',
      mimeType: 'application/pdf',
      fileKind: 'pdf',
      extension: 'pdf',
      sizeBytes: 1024,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}

PickedDocument _makePickedPdf(String name) {
  return PickedDocument(
    name: name,
    sizeBytes: 1024,
    mimeType: 'application/pdf',
    bytes: Uint8List.fromList([1, 2, 3]),
  );
}

void main() {
  group('Compiled Document Models', () {
    test('CompiledDocumentProposal parses from JSON and serializes', () {
      final json = {
        'startPage': 1,
        'endPage': 2,
        'categoryKey': 'curriculum-vitae',
        'folderKey': 'curriculum-vitae',
        'title': 'My Resume',
        'documentDate': '2024-05-10',
        'confidence': 0.95,
      };

      final proposal = CompiledDocumentProposal.fromJson(json);
      expect(proposal.startPage, 1);
      expect(proposal.endPage, 2);
      expect(proposal.categoryKey, 'curriculum-vitae');
      expect(proposal.folderKey, 'curriculum-vitae');
      expect(proposal.title, 'My Resume');
      expect(proposal.documentDate, DateTime(2024, 5, 10));
      expect(proposal.confidence, 0.95);

      final copy = proposal.copyWith(title: 'Updated Resume');
      expect(copy.title, 'Updated Resume');
      expect(copy.startPage, 1);
    });

    test('CompiledAnalysisResult parses from JSON', () {
      final json = {
        'sessionId': 'csess_123',
        'originalFileName': 'compiled_portfolio.pdf',
        'totalPages': 5,
        'documents': [
          {
            'startPage': 1,
            'endPage': 2,
            'categoryKey': 'curriculum-vitae',
            'folderKey': 'curriculum-vitae',
            'title': 'Curriculum Vitae',
            'documentDate': '2024-01-01',
          },
          {
            'startPage': 3,
            'endPage': 5,
            'categoryKey': 'certificates',
            'folderKey': 'seminars',
            'title': 'Flutter Certificate',
            'documentDate': '2024-05-15',
          },
        ],
      };

      final result = CompiledAnalysisResult.fromJson(json);
      expect(result.sessionId, 'csess_123');
      expect(result.totalPages, 5);
      expect(result.originalFileName, 'compiled_portfolio.pdf');
      expect(result.documents.length, 2);
      expect(result.documents[0].startPage, 1);
      expect(result.documents[1].startPage, 3);
    });

    test('CompiledSplitSegment serializes to JSON accurately', () {
      final seg = CompiledSplitSegment(
        startPage: 1,
        endPage: 3,
        categoryKey: 'certificates',
        folderKey: 'seminars',
        title: 'Seminar Certificate',
        documentDate: DateTime(2024, 8, 20),
        description: 'Attended mobile seminar',
        reflection: 'Learned a lot',
      );

      final json = seg.toJson();
      expect(json['startPage'], 1);
      expect(json['endPage'], 3);
      expect(json['categoryKey'], 'certificates');
      expect(json['folderKey'], 'seminars');
      expect(json['title'], 'Seminar Certificate');
      expect(json['documentDate'], '2024-08-20');
      expect(json['description'], 'Attended mobile seminar');
      expect(json['reflection'], 'Learned a lot');
    });
  });

  group('Batch Upload Auto-Categorization (Mode B)', () {
    test(
      'auto-categorizes items from metadata suggestions when category has not been manually changed',
      () async {
        final service = _BatchTestDocService();
        service.nextSuggestions = DocumentMetadataSuggestions(
          categoryKey: 'certificates',
          folderKey: 'seminars',
          title: 'AI Detected Seminar',
          documentDate: DateTime(2024, 6, 1),
          confidence: 'high',
        );

        final queue = BatchUploadQueue(documentService: service);
        final file = _makePickedPdf('scan1.pdf');

        queue.initialize(
          [file],
          defaultCategoryKey: 'curriculum-vitae',
          defaultFolderKey: 'curriculum-vitae',
          autoStart: false,
        );

        expect(queue.items.first.isManualCategory, false);
        expect(queue.items.first.isAutoCategorized, false);

        await queue.startProcessing();

        final item = queue.items.first;
        expect(item.status, BatchItemStatus.completed);
        expect(item.categoryKey, 'certificates');
        expect(item.folderKey, 'seminars');
        expect(item.title, 'AI Detected Seminar');
        expect(item.isAutoCategorized, true);
        expect(service.updateMetadataCallCount, greaterThan(0));
      },
    );

    test(
      'manual category selection protects item from being overwritten by auto-categorization',
      () async {
        final service = _BatchTestDocService();
        service.nextSuggestions = DocumentMetadataSuggestions(
          categoryKey: 'certificates',
          folderKey: 'seminars',
          title: 'AI Detected Seminar',
          confidence: 'high',
        );

        final queue = BatchUploadQueue(documentService: service);
        final file = _makePickedPdf('scan2.pdf');

        queue.initialize(
          [file],
          defaultCategoryKey: 'curriculum-vitae',
          defaultFolderKey: 'curriculum-vitae',
          autoStart: false,
        );

        // User manually sets the category before OCR runs
        queue.updateItemMetadata(
          queue.items.first.id,
          categoryKey: 'curriculum-vitae',
          folderKey: 'curriculum-vitae',
          isManual: true,
        );

        expect(queue.items.first.isManualCategory, true);

        await queue.startProcessing();

        // OCR completed, but manual category choice MUST NOT be overwritten
        final item = queue.items.first;
        expect(item.status, BatchItemStatus.completed);
        expect(item.categoryKey, 'curriculum-vitae');
        expect(item.isAutoCategorized, false);
      },
    );
  });

  group('CompiledReviewScreen Widget Tests (Mode C)', () {
    testWidgets('renders document proposal cards and page boundaries', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = _MockCompiledDocService();
      final file = _makePickedPdf('compiled_portfolio.pdf');

      final analysis = CompiledAnalysisResult(
        sessionId: 'csess_widget_test',
        originalFileName: 'compiled_portfolio.pdf',
        totalPages: 4,
        documents: const [
          CompiledDocumentProposal(
            startPage: 1,
            endPage: 2,
            categoryKey: 'curriculum-vitae',
            folderKey: 'curriculum-vitae',
            title: 'Resume Section',
          ),
          CompiledDocumentProposal(
            startPage: 3,
            endPage: 4,
            categoryKey: 'certificates',
            folderKey: 'seminars',
            title: 'Seminar Section',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentScope(
            documentService: service,
            child: CompiledReviewScreen(analysis: analysis, file: file),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Header verification
      expect(find.text('compiled_portfolio.pdf'), findsOneWidget);
      expect(find.text('4 Pages'), findsOneWidget);
      expect(find.text('Separate Portfolio (2 Docs)'), findsOneWidget);

      // Proposals rendered
      expect(find.text('Document 1'), findsOneWidget);
      expect(find.text('Document 2'), findsOneWidget);
      expect(find.text('Resume Section'), findsOneWidget);
      expect(find.text('Seminar Section'), findsOneWidget);
    });

    testWidgets('splitting triggers splitCompiledDocument and pops with true', (
      tester,
    ) async {
      final service = _MockCompiledDocService();
      final file = _makePickedPdf('compiled_portfolio.pdf');

      final analysis = CompiledAnalysisResult(
        sessionId: 'csess_split_test',
        originalFileName: 'compiled_portfolio.pdf',
        totalPages: 2,
        documents: [
          CompiledDocumentProposal(
            startPage: 1,
            endPage: 1,
            categoryKey: 'curriculum-vitae',
            folderKey: 'curriculum-vitae',
            title: 'Doc 1',
            documentDate: DateTime(2026, 1, 1),
          ),
          CompiledDocumentProposal(
            startPage: 2,
            endPage: 2,
            categoryKey: 'certificates',
            folderKey: 'seminars',
            title: 'Doc 2',
            documentDate: DateTime(2026, 1, 2),
          ),
        ],
      );

      bool? returnedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  returnedResult = await Navigator.push<bool>(
                    ctx,
                    MaterialPageRoute(
                      builder: (c) => DocumentScope(
                        documentService: service,
                        child: CompiledReviewScreen(
                          analysis: analysis,
                          file: file,
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open Compiled Review'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Compiled Review'));
      await tester.pumpAndSettle();

      // Tap "Separate & Save (2)" button
      final saveBtn = find.text('Separate & Save (2)');
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(service.splitCallCount, 1);
      expect(service.lastSplitSegments?.length, 2);
      expect(returnedResult, true);
    });
  });
}
