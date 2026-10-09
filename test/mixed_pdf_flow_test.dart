import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/screens/files/add_file_screen.dart';
import 'package:proport_app/screens/files/compiled_review_screen.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/document_models.dart';
import 'package:proport_app/services/document_scope.dart';
import 'package:proport_app/services/document_service.dart';
import 'package:proport_app/services/secure_token_store.dart';

class _TokenStore implements SecureTokenStore {
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> writeRefreshToken(String value) async {}
  @override
  Future<void> deleteRefreshToken() async {}
}

class _Documents extends DocumentService {
  _Documents(this.nextAnalysis)
    : super(
        authService: AuthService(
          apiClient: ApiClient(baseUrl: 'http://example.test:3000'),
          tokenStore: _TokenStore(),
        ),
      );
  Future<CompiledAnalysisResult> nextAnalysis;
  Completer<void>? categoryLoading;
  int analysisCalls = 0;
  int previewCalls = 0;
  bool failFirstSplit = false;
  bool cancellationSucceeds = true;
  final cancelledSessions = <String>[];
  final splitKeys = <String>[];
  final splitPayloads = <List<Map<String, dynamic>>>[];
  @override
  List<DocumentCategory> get categories => const [
    DocumentCategory(
      key: 'certificates',
      name: 'Certificates',
      folders: [DocumentFolder(key: 'seminars', name: 'Seminars')],
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
  Future<void> load({bool force = false}) async {
    await categoryLoading?.future;
  }

  @override
  Future<CompiledAnalysisResult> analyzeCompiledDocument(
    PickedDocument file,
  ) async {
    analysisCalls++;
    return nextAnalysis;
  }

  @override
  Future<DocumentOcrResult> previewOcr(dynamic fileOrFiles) async {
    previewCalls++;
    throw StateError('PDF analysis must not call a second OCR preview');
  }

  @override
  Future<bool> cancelCompiledSession(String sessionId) async {
    cancelledSessions.add(sessionId);
    return cancellationSucceeds;
  }

  @override
  Future<List<DocumentRecord>> splitCompiledDocument({
    required String sessionId,
    required String idempotencyKey,
    required List<CompiledSplitSegment> segments,
  }) async {
    splitKeys.add(idempotencyKey);
    splitPayloads.add(segments.map((segment) => segment.toJson()).toList());
    if (failFirstSplit && splitKeys.length == 1) {
      throw const ApiException(
        code: 'NETWORK_TIMEOUT',
        message: 'Response lost; retry safely.',
      );
    }
    return [];
  }
}

PickedDocument _file() => PickedDocument(
  name: 'mixed.pdf',
  sizeBytes: 5,
  mimeType: 'application/pdf',
  bytes: Uint8List.fromList([37, 80, 68, 70, 45]),
);

CompiledDocumentProposal _proposal(int start, int end, {bool cv = false}) =>
    CompiledDocumentProposal(
      startPage: start,
      endPage: end,
      categoryKey: cv ? 'curriculum-vitae' : 'certificates',
      folderKey: cv ? 'curriculum-vitae' : 'seminars',
      title: cv ? 'My CV' : 'Certificate',
      documentDate: DateTime(2026, 5, 1),
      confidence: 0.9,
    );

CompiledAnalysisResult _analysis({
  bool single = false,
  bool unresolved = false,
  String session = 'session_one',
  List<CompiledDocumentProposal>? proposals,
}) => CompiledAnalysisResult(
  sessionId: session,
  originalFileName: 'mixed.pdf',
  totalPages: 3,
  detection: unresolved
      ? 'needs_review'
      : single
      ? 'single'
      : 'multiple',
  documents:
      proposals ??
      (single
          ? [_proposal(1, 3, cv: true)]
          : [_proposal(1, 1), _proposal(2, 3, cv: true)]),
  pages: List.generate(
    3,
    (index) => CompiledPageResult(
      pageNumber: index + 1,
      text: 'Preserved page text',
      source: unresolved && index == 1
          ? 'failed'
          : index == 0
          ? 'digital'
          : 'ocr',
      status: unresolved && index == 1 ? 'unresolved' : 'ready',
    ),
  ),
);

Future<void> _open(
  WidgetTester tester,
  _Documents service,
  Widget screen,
) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    DocumentScope(documentService: service, child: screen),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _save(WidgetTester tester, int count) async {
  // Floating feedback temporarily overlays the bottom action; wait for it to close.
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Separate & Save ($count)'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('failed-page JSON with unknown taxonomy reaches manual review', (
    tester,
  ) async {
    final analysis = CompiledAnalysisResult.fromJson({
      'sessionId': 'unresolved_json',
      'originalFileName': 'unreadable.pdf',
      'totalPages': 1,
      'detection': 'needs_review',
      'pages': [
        {
          'pageNumber': 1,
          'text': '',
          'source': 'failed',
          'status': 'unresolved',
        },
      ],
      'documents': [
        {
          'startPage': 1,
          'endPage': 1,
          'categoryKey': '',
          'folderKey': '',
          'title': 'Unreadable page — retry required',
          'documentDate': null,
          'confidence': 0,
        },
      ],
    });
    final service = _Documents(Future.value(analysis));
    await _open(tester, service, AddFileScreen(initialFiles: [_file()]));
    await tester.pumpAndSettle();
    expect(find.byType(CompiledReviewScreen), findsOneWidget);
    expect(find.textContaining('Unreadable pages: 1'), findsOneWidget);
    expect(find.text('Select Category'), findsOneWidget);
    await _save(tester, 1);
    expect(service.splitKeys, isEmpty);
  });

  testWidgets(
    'manual edit while categories load prevents late automatic navigation',
    (tester) async {
      final service = _Documents(Future.value(_analysis()))
        ..categoryLoading = Completer<void>();
      await _open(tester, service, AddFileScreen(initialFiles: [_file()]));
      await tester.enterText(
        find.byType(TextField).first,
        'Edited while loading',
      );
      service.categoryLoading!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CompiledReviewScreen), findsNothing);
      expect(find.text('Edited while loading'), findsOneWidget);
      expect(find.textContaining('Your edits are preserved'), findsOneWidget);
    },
  );

  testWidgets(
    'adding a mixed PDF automatically opens review and reuses one analysis',
    (tester) async {
      final service = _Documents(Future.value(_analysis()));
      await _open(tester, service, AddFileScreen(initialFiles: [_file()]));
      await tester.pumpAndSettle();
      expect(find.byType(CompiledReviewScreen), findsOneWidget);
      expect(service.analysisCalls, 1);
      expect(service.previewCalls, 0);
      expect(
        service.splitKeys,
        isEmpty,
      ); // Review is required, never automatic splitting.
      expect(find.text('My CV'), findsOneWidget);
    },
  );

  testWidgets(
    'three-page CV stays in normal Add File and manual Separate reuses analysis',
    (tester) async {
      final service = _Documents(Future.value(_analysis(single: true)));
      await _open(tester, service, AddFileScreen(initialFiles: [_file()]));
      await tester.pumpAndSettle();
      expect(find.byType(CompiledReviewScreen), findsNothing);
      expect(find.text('My CV'), findsOneWidget);
      await tester.tap(find.text('Separate'));
      await tester.pumpAndSettle();
      expect(find.byType(CompiledReviewScreen), findsOneWidget);
      expect(find.text('Separate & Save (1)'), findsOneWidget);
      expect(service.analysisCalls, 1);
      expect(service.previewCalls, 0);
    },
  );

  testWidgets(
    'late multiple-document result preserves manual title and stays in Add File',
    (tester) async {
      final pending = Completer<CompiledAnalysisResult>();
      final service = _Documents(pending.future);
      await _open(tester, service, AddFileScreen(initialFiles: [_file()]));
      await tester.enterText(find.byType(TextField).first, 'My reviewed title');
      pending.complete(_analysis());
      await tester.pumpAndSettle();
      expect(find.byType(CompiledReviewScreen), findsNothing);
      expect(find.text('My reviewed title'), findsOneWidget);
      expect(find.textContaining('Your edits are preserved'), findsOneWidget);
    },
  );

  testWidgets(
    'lost split response retries identical key and reviewed payload',
    (tester) async {
      final service = _Documents(Future.value(_analysis()))
        ..failFirstSplit = true;
      await _open(
        tester,
        service,
        CompiledReviewScreen(analysis: _analysis(), file: _file()),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'Reviewed certificate',
      );
      await _save(tester, 2);
      expect(find.text('Response lost; retry safely.'), findsOneWidget);
      await _save(tester, 2);
      expect(service.splitKeys, hasLength(2));
      expect(service.splitKeys[1], service.splitKeys[0]);
      expect(service.splitPayloads[1], service.splitPayloads[0]);
      expect(service.splitPayloads[0][0]['title'], 'Reviewed certificate');
      expect(find.byType(CompiledReviewScreen), findsNothing);
    },
  );

  for (final invalid in [
    [_proposal(1, 2), _proposal(2, 3, cv: true)],
    [_proposal(1, 1), _proposal(3, 3, cv: true)],
    [_proposal(1, 2)],
  ]) {
    testWidgets(
      'rejects invalid reviewed page coverage ${invalid.map((p) => '${p.startPage}-${p.endPage}').join(',')}',
      (tester) async {
        final analysis = _analysis(proposals: invalid);
        final service = _Documents(Future.value(analysis));
        await _open(
          tester,
          service,
          CompiledReviewScreen(analysis: analysis, file: _file()),
        );
        await tester.pumpAndSettle();
        await _save(tester, invalid.length);
        expect(service.splitKeys, isEmpty);
        expect(find.byType(CompiledReviewScreen), findsOneWidget);
      },
    );
  }

  testWidgets(
    'unreadable page blocks split and retry preserves reviewed title',
    (tester) async {
      final service = _Documents(
        Future.value(_analysis(session: 'session_retry')),
      );
      await _open(
        tester,
        service,
        CompiledReviewScreen(
          analysis: _analysis(unresolved: true),
          file: _file(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Unreadable pages: 2'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Keep my title');
      await _save(tester, 2);
      expect(service.splitKeys, isEmpty);
      await tester.tap(find.text('Retry PDF analysis'));
      await tester.pumpAndSettle();
      expect(find.text('Keep my title'), findsOneWidget);
      expect(service.cancelledSessions, contains('session_one'));
      expect(find.textContaining('Unreadable pages: 2'), findsNothing);
      await _save(tester, 2);
      expect(service.splitPayloads.single.first['title'], 'Keep my title');
    },
  );

  testWidgets(
    'failed cancellation stays in review; successful retry cleans before leaving',
    (tester) async {
      final service = _Documents(Future.value(_analysis()))
        ..cancellationSucceeds = false;
      await _open(
        tester,
        service,
        CompiledReviewScreen(analysis: _analysis(), file: _file()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(CompiledReviewScreen), findsOneWidget);
      expect(find.textContaining('cleanup could not finish'), findsOneWidget);
      service.cancellationSucceeds = true;
      // Android back uses the same guarded cancellation path.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(service.cancelledSessions, ['session_one', 'session_one']);
      expect(find.byType(CompiledReviewScreen), findsNothing);
    },
  );

  testWidgets(
    'unmounting normal single-PDF flow releases its temporary session',
    (tester) async {
      final service = _Documents(Future.value(_analysis(single: true)));
      await _open(tester, service, AddFileScreen(initialFiles: [_file()]));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(service.cancelledSessions, ['session_one']);
    },
  );
}
