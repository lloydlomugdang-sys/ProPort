import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_models.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/document_models.dart';
import 'package:proport_app/services/document_service.dart';
import 'package:proport_app/services/secure_token_store.dart';

void main() {
  test(
    'previews authenticated file bytes with OCR timeout without adding a document',
    () async {
      final auth = _DocumentAuthService();
      final service = DocumentService(authService: auth);
      auth.ocrResponse = _envelope({
        'ocr': {
          'status': 'ready',
          'rawText': 'OCR fixture',
          'metadataAnalysis': {'source': 'gemini', 'aiStatus': 'success'},
          'metadataSuggestions': {
            'categoryKey': 'certificates',
            'folderKey': 'trainings',
            'title': 'Digital Records Management',
            'documentDate': '2026-09-14',
            'description':
                'Certificate of Completion for Digital Records Management.',
          },
        },
      });
      final file = PickedDocument(
        name: 'course.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([137, 80, 78, 71]),
      );
      final result = await service.previewOcr(file);
      expect(result.metadataSuggestions?.title, 'Digital Records Management');
      expect(result.metadataAnalysis?.source, 'gemini');
      expect(result.metadataAnalysis?.aiStatus, 'success');
      expect(result.metadataSuggestions?.documentDate, DateTime(2026, 9, 14));
      expect(auth.uploadPath, '/api/v1/documents/ocr-preview');
      expect(auth.uploadFields, isEmpty);
      expect(auth.uploadBytes, same(file.bytes));
      expect(auth.ocrPostTimeout, DocumentService.ocrPreviewTimeout);
      expect(service.documents, isEmpty);
      expect(service.summary.totalCount, 0);
      service.dispose();
      auth.dispose();
    },
  );

  test(
    'rejects malformed suggestion dates and supports older OCR responses',
    () {
      for (final date in ['2026-02-30', '09/14/2026', '2026-9-14', 'garbage']) {
        expect(
          () => DocumentMetadataSuggestions.fromJson({'documentDate': date}),
          throwsFormatException,
        );
      }
      expect(
        DocumentOcrResult.fromJson({
          'status': 'ready',
          'rawText': 'Legacy response',
        }).metadataSuggestions,
        isNull,
      );
      expect(DocumentMetadataSuggestions.fromJson({}).isEmpty, isTrue);
      expect(
        DocumentOcrResult.fromJson({'status': 'ready'}).metadataAnalysis,
        isNull,
      );
      expect(
        () => DocumentOcrResult.fromJson({
          'status': 'ready',
          'metadataAnalysis': {'source': 'invented', 'aiStatus': 'success'},
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'client upload policy accepts only matching PDF/JPEG/PNG names and MIME types',
    () {
      PickedDocument picked(String name, String mimeType) =>
          PickedDocument(name: name, mimeType: mimeType, bytes: Uint8List(1));

      expect(
        picked('resume.pdf', 'application/pdf').hasSupportedUploadType,
        isTrue,
      );
      expect(picked('photo.jpg', 'image/jpeg').hasSupportedUploadType, isTrue);
      expect(picked('photo.JPEG', 'image/jpeg').hasSupportedUploadType, isTrue);
      expect(picked('award.png', 'image/png').hasSupportedUploadType, isTrue);
      expect(picked('fake.pdf', 'image/png').hasSupportedUploadType, isFalse);
      expect(picked('notes.txt', 'text/plain').hasSupportedUploadType, isFalse);
    },
  );

  test('loads seeded categories, owned documents, and server counts', () async {
    final auth = _DocumentAuthService();
    final service = DocumentService(authService: auth);

    await service.load();

    expect(auth.getPaths, [
      '/api/v1/documents/categories',
      '/api/v1/documents',
    ]);
    expect(service.categories.single.name, 'Certificates');
    expect(service.categories.single.folders.single.name, 'Seminars');
    expect(service.documents.single.originalFileName, 'certificate.pdf');
    expect(service.summary.totalCount, 1);
    expect(service.summary.folderCount('certificates', 'seminars'), 1);
    expect(service.hasLoadedDocuments, isTrue);
    expect(service.hasLoadedCategories, isTrue);

    service.dispose();
    auth.dispose();
  });

  test(
    'uploads real bytes and updates shared document state immediately',
    () async {
      final auth = _DocumentAuthService();
      final service = DocumentService(authService: auth);
      await service.load();
      auth.uploadResponse = _envelope({
        'document': _documentJson(
          id: 'document-2',
          fileName: 'award.png',
          mimeType: 'image/png',
          fileKind: 'image',
          extension: 'png',
        ),
      });
      final bytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);

      final uploaded = await service.upload(
        file: PickedDocument(
          name: 'award.png',
          mimeType: 'image/png',
          bytes: bytes,
        ),
        categoryKey: 'certificates',
        folderKey: 'seminars',
        title: 'PNG Award',
        documentDate: DateTime(2026, 9, 11),
        description: 'kept as metadata',
      );

      expect(uploaded.id, 'document-2');
      expect(auth.uploadPath, '/api/v1/documents');
      expect(auth.uploadFileName, 'award.png');
      expect(auth.uploadMimeType, 'image/png');
      expect(auth.uploadBytes, same(bytes));
      expect(auth.uploadFields, {
        'categoryKey': 'certificates',
        'folderKey': 'seminars',
        'title': 'PNG Award',
        'documentDate': '2026-09-11',
        'description': 'kept as metadata',
      });
      expect(auth.uploadFields, isNot(contains('ownerId')));
      expect(auth.uploadFields, isNot(contains('fileBytes')));
      expect(service.documents.first.id, 'document-2');
      expect(service.summary.totalCount, 2);
      expect(service.summary.folderCount('certificates', 'seminars'), 2);

      service.dispose();
      auth.dispose();
    },
  );

  test(
    'deletes through the owned endpoint and updates counts immediately',
    () async {
      final auth = _DocumentAuthService();
      final service = DocumentService(authService: auth);
      await service.load();

      await service.delete('document-1');

      expect(auth.deletePaths, ['/api/v1/documents/document-1']);
      expect(service.documents, isEmpty);
      expect(service.summary.totalCount, 0);
      expect(service.summary.folderCount('certificates', 'seminars'), 0);

      service.dispose();
      auth.dispose();
    },
  );

  test(
    'loads, extracts with a dedicated timeout, and saves reviewed OCR text',
    () async {
      final auth = _DocumentAuthService();
      final service = DocumentService(authService: auth);

      final initial = await service.loadOcr('document-1');
      expect(initial.status, DocumentOcrStatus.notProcessed);

      auth.ocrResponse = _ocrEnvelope(
        status: 'ready',
        rawText: 'Raw OCR text',
        reviewedText: 'Raw OCR text',
      );
      final extracted = await service.extractText('document-1');
      expect(extracted.status, DocumentOcrStatus.ready);
      expect(extracted.rawText, 'Raw OCR text');
      expect(auth.ocrPostPath, '/api/v1/documents/document-1/ocr');
      expect(auth.ocrPostBody, isEmpty);
      expect(auth.ocrPostTimeout, DocumentService.ocrRequestTimeout);

      auth.ocrResponse = _ocrEnvelope(
        status: 'ready',
        rawText: 'Raw OCR text',
        reviewedText: 'Corrected OCR text',
      );
      final saved = await service.saveReviewedText(
        'document-1',
        'Corrected OCR text',
      );
      expect(saved.reviewedText, 'Corrected OCR text');
      expect(auth.ocrPatchPath, '/api/v1/documents/document-1/ocr');
      expect(auth.ocrPatchBody, {'reviewedText': 'Corrected OCR text'});
      expect(auth.ocrPatchBody, isNot(contains('rawText')));
      expect(service.ocrFor('document-1')?.reviewedText, 'Corrected OCR text');

      auth.switchUser(_authUser('user-2'));
      expect(service.ocrFor('document-1'), isNull);

      service.dispose();
      auth.dispose();
    },
  );

  test(
    'exposes safe API errors and keeps failed uploads out of state',
    () async {
      final auth = _DocumentAuthService()
        ..getFailure = const ApiException(
          code: 'DOCUMENT_UNAVAILABLE',
          message: 'Documents are temporarily unavailable. Please try again.',
          statusCode: 503,
        );
      final service = DocumentService(authService: auth);

      await expectLater(service.load(), throwsA(isA<ApiException>()));

      expect(
        service.errorMessage,
        'Documents are temporarily unavailable. Please try again.',
      );
      expect(service.hasLoadedDocuments, isFalse);
      expect(service.documents, isEmpty);

      service.dispose();
      auth.dispose();
    },
  );

  test(
    'an account switch prevents an older in-flight list from repopulating state',
    () async {
      final auth = _DocumentAuthService();
      auth.pendingDocuments = Completer<Map<String, dynamic>>();
      final service = DocumentService(authService: auth);

      final pendingLoad = service.load();
      while (!auth.getPaths.contains('/api/v1/documents')) {
        await Future<void>.delayed(Duration.zero);
      }
      auth.switchUser(_authUser('user-2'));
      auth.pendingDocuments!.complete(
        _envelope({
          'documents': [_documentJson()],
          'summary': {
            'totalCount': 1,
            'categoryCounts': {'certificates': 1},
            'folderCounts': {'certificates/seminars': 1},
          },
        }),
      );
      await pendingLoad;

      expect(service.documents, isEmpty);
      expect(service.summary.totalCount, 0);
      expect(service.hasLoadedDocuments, isFalse);

      service.dispose();
      auth.dispose();
    },
  );
}

class _DocumentAuthService extends AuthService {
  _DocumentAuthService()
    : super(
        apiClient: ApiClient(baseUrl: 'http://example.test:3000'),
        tokenStore: _NoopTokenStore(),
      );

  final List<String> getPaths = [];
  final List<String> deletePaths = [];
  ApiException? getFailure;
  Map<String, dynamic>? uploadResponse;
  Map<String, dynamic> ocrResponse = _ocrEnvelope(status: 'not_processed');
  String? ocrPostPath;
  Map<String, dynamic>? ocrPostBody;
  Duration? ocrPostTimeout;
  String? ocrPatchPath;
  Map<String, dynamic>? ocrPatchBody;
  String? uploadPath;
  Map<String, String>? uploadFields;
  String? uploadFileName;
  String? uploadMimeType;
  Uint8List? uploadBytes;
  Completer<Map<String, dynamic>>? pendingDocuments;
  AuthUser _currentUser = _authUser('user-1');

  @override
  AuthUser? get user => _currentUser;

  void switchUser(AuthUser value) {
    _currentUser = value;
    notifyListeners();
  }

  @override
  Future<Map<String, dynamic>> authenticatedGetJson(String path) async {
    getPaths.add(path);
    final failure = getFailure;
    if (failure != null) throw failure;
    if (path.endsWith('/categories')) {
      return _envelope({
        'categories': [
          {
            'key': 'certificates',
            'name': 'Certificates',
            'folders': [
              {'key': 'seminars', 'name': 'Seminars'},
            ],
          },
        ],
      });
    }
    if (path.endsWith('/ocr')) return ocrResponse;
    if (pendingDocuments != null) return pendingDocuments!.future;
    return _envelope({
      'documents': [_documentJson()],
      'summary': {
        'totalCount': 1,
        'categoryCounts': {'certificates': 1},
        'folderCounts': {'certificates/seminars': 1},
      },
    });
  }

  @override
  Future<Map<String, dynamic>> authenticatedPostJsonWithTimeout(
    String path, {
    required Map<String, dynamic> body,
    required Duration timeout,
  }) async {
    ocrPostPath = path;
    ocrPostBody = Map.of(body);
    ocrPostTimeout = timeout;
    return ocrResponse;
  }

  @override
  Future<Map<String, dynamic>> authenticatedPatchJson(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    ocrPatchPath = path;
    ocrPatchBody = Map.of(body);
    return ocrResponse;
  }

  @override
  Future<Map<String, dynamic>> authenticatedPostMultipart(
    String path, {
    required Map<String, String> fields,
    required String fileName,
    required String mimeType,
    required Uint8List fileBytes,
    Duration? requestTimeout,
  }) async {
    uploadPath = path;
    uploadFields = Map.of(fields);
    uploadFileName = fileName;
    uploadMimeType = mimeType;
    uploadBytes = fileBytes;
    if (path.endsWith('/ocr-preview')) {
      ocrPostTimeout = requestTimeout;
      return ocrResponse;
    }
    return uploadResponse ?? _envelope({'document': _documentJson()});
  }

  @override
  Future<Map<String, dynamic>> authenticatedDeleteJson(String path) async {
    deletePaths.add(path);
    return _envelope({'status': 'deleted', 'documentId': 'document-1'});
  }
}

class _NoopTokenStore implements SecureTokenStore {
  @override
  Future<void> deleteRefreshToken() async {}

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> writeRefreshToken(String refreshToken) async {}
}

Map<String, dynamic> _envelope(Map<String, dynamic> data) => {
  'data': data,
  'meta': {'requestId': 'document-test'},
};

Map<String, dynamic> _ocrEnvelope({
  required String status,
  String? rawText,
  String? reviewedText,
}) => _envelope({
  'ocr': {
    'status': status,
    'rawText': ?rawText,
    'reviewedText': ?reviewedText,
    if (status == 'ready') ...{
      'engine': 'tesseract.js',
      'processedAt': '2026-09-12T00:00:00.000Z',
      'updatedAt': '2026-09-12T00:00:00.000Z',
    },
  },
});

Map<String, dynamic> _documentJson({
  String id = 'document-1',
  String fileName = 'certificate.pdf',
  String mimeType = 'application/pdf',
  String fileKind = 'pdf',
  String extension = 'pdf',
}) => {
  'id': id,
  'categoryKey': 'certificates',
  'folderKey': 'seminars',
  'title': 'Certificate',
  'documentDate': '2026-09-11T00:00:00.000Z',
  'originalFileName': fileName,
  'mimeType': mimeType,
  'fileKind': fileKind,
  'extension': extension,
  'sizeBytes': 128,
  'createdAt': '2026-09-11T01:00:00.000Z',
  'updatedAt': '2026-09-11T01:00:00.000Z',
};

AuthUser _authUser(String id) => AuthUser(
  id: id,
  email: '$id@example.edu',
  firstName: 'Grad',
  lastName: 'Student',
  program: '',
  yearLevel: '',
  school: '',
  status: 'active',
  emailVerifiedAt: DateTime.utc(2026, 9, 11),
);
