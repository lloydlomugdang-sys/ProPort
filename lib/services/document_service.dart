import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'app_ocr_coordinator.dart';
import 'auth_service.dart';
import 'document_models.dart';
import 'pdf_thumbnail_renderer.dart';

class DocumentService extends ChangeNotifier {
  DocumentService({
    required AuthService authService,
    AppOcrCoordinator? ocrCoordinator,
  }) : _authService = authService,
       _ocrCoordinator = ocrCoordinator ?? AppOcrCoordinator(maxConcurrent: 1),
       _authenticatedUserId = authService.user?.id {
    _authService.addListener(_handleAuthChanged);
  }

  final AppOcrCoordinator _ocrCoordinator;
  AppOcrCoordinator get ocrCoordinator => _ocrCoordinator;

  static const maxUploadBytes = 15 * 1024 * 1024;
  static const ocrRequestTimeout = Duration(seconds: 60);
  // Preview includes upload, a possible cold start and the backend's bounded
  // 45-second OCR job plus bounded Gemini analysis (at most 30 seconds).
  // Keep ordinary API requests on their existing timeout.
  static const ocrPreviewTimeout = Duration(seconds: 120);
  // Compiled analysis has its own 90-second extraction budget, up to 30 seconds
  // of text-only AI, plus upload/storage/cold-start headroom.
  static const compiledAnalysisTimeout = Duration(seconds: 150);
  static const _documentsPath = '/api/v1/documents';

  final AuthService _authService;
  String? _authenticatedUserId;
  List<DocumentRecord> _documents = const [];
  List<DocumentCategory> _categories = const [];
  DocumentSummary _summary = DocumentSummary.empty;
  bool _hasLoadedDocuments = false;
  bool _hasLoadedCategories = false;
  bool _isLoading = false;
  String? _errorMessage;
  final Map<String, DocumentOcrResult> _ocrResults = {};
  final Set<String> _extractingDocumentIds = {};

  /// Maximum cached raw content entries (30 entries / 30 MiB ceiling).
  static const int maxCachedEntries = 30;
  static const int maxCachedDocuments = maxCachedEntries;
  static const int maxCachedBytes =
      30 * 1024 * 1024; // 30 MiB mobile-safe ceiling
  final Map<String, Uint8List> _contentCache = {};
  int _currentCachedBytes = 0;
  final Map<String, Future<Uint8List>> _inFlightContentRequests = {};

  /// Separate bounded cache for page-1 thumbnails (30 entries / 10 MiB ceiling)
  /// so rendering thumbnails never reduces raw-content cache capacity.
  static const int maxCachedThumbnails = 30;
  static const int maxCachedThumbnailBytes = 10 * 1024 * 1024; // 10 MiB ceiling
  final Map<String, Uint8List> _thumbnailCache = {};
  int _currentCachedThumbnailBytes = 0;
  final Map<String, Future<Uint8List?>> _inFlightThumbnailRequests = {};
  PdfThumbnailRenderer _pdfThumbnailRenderer =
      const DefaultPdfThumbnailRenderer();
  int _authGeneration = 0;
  int _loadOperation = 0;

  List<DocumentRecord> get documents => List.unmodifiable(_documents);
  List<DocumentCategory> get categories => List.unmodifiable(_categories);
  DocumentSummary get summary => _summary;
  int get currentCachedBytes => _currentCachedBytes;
  int get currentCachedThumbnailBytes => _currentCachedThumbnailBytes;

  @visibleForTesting
  set pdfThumbnailRenderer(PdfThumbnailRenderer renderer) {
    _pdfThumbnailRenderer = renderer;
  }

  bool get hasLoadedDocuments => _hasLoadedDocuments;
  bool get hasLoadedCategories => _hasLoadedCategories;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DocumentOcrResult? ocrFor(String documentId) => _ocrResults[documentId];
  bool isExtractingText(String documentId) =>
      _extractingDocumentIds.contains(documentId);

  Future<void> load({bool force = false}) async {
    if (_isLoading) return;
    if (!force && _hasLoadedDocuments && _hasLoadedCategories) return;
    final authGeneration = _authGeneration;
    final loadOperation = ++_loadOperation;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final shouldLoadCategories = force || !_hasLoadedCategories;
    final shouldLoadDocuments = force || !_hasLoadedDocuments;

    Object? categoriesError;
    StackTrace? categoriesStackTrace;
    Object? documentsError;
    StackTrace? documentsStackTrace;

    final futures = <Future<void>>[];

    if (shouldLoadCategories) {
      futures.add(
        _loadCategories(authGeneration).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          categoriesError = error;
          categoriesStackTrace = stackTrace;
        }),
      );
    }

    if (shouldLoadDocuments) {
      futures.add(
        _loadDocuments(authGeneration).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          documentsError = error;
          documentsStackTrace = stackTrace;
        }),
      );
    }

    try {
      if (futures.isNotEmpty) {
        await Future.wait(futures);
      }

      if (authGeneration != _authGeneration) return;

      final firstError = categoriesError ?? documentsError;
      final firstStackTrace = categoriesStackTrace ?? documentsStackTrace;
      if (firstError != null) {
        if (firstError is ApiException) {
          _errorMessage = firstError.message;
        } else {
          _errorMessage = 'Unable to load documents. Please try again.';
        }
        Error.throwWithStackTrace(
          firstError,
          firstStackTrace ?? StackTrace.current,
        );
      }
    } finally {
      if (loadOperation == _loadOperation) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

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
    final effectiveFiles =
        files ?? (file != null ? [file] : const <PickedDocument>[]);
    if (effectiveFiles.isEmpty) {
      throw const ApiException(
        code: 'VALIDATION_ERROR',
        message: 'At least one file is required.',
        statusCode: 400,
      );
    }
    final authGeneration = _authGeneration;
    final fields = {
      'categoryKey': categoryKey,
      'folderKey': folderKey,
      'title': title,
      'documentDate': _dateOnly(documentDate),
      if (description != null && description.trim().isNotEmpty)
        'description': description,
      if (reflection != null && reflection.trim().isNotEmpty)
        'reflection': reflection,
    };

    final uploadedBytes = <Uint8List>[];
    final Map<String, dynamic> response;
    if (effectiveFiles.length == 1) {
      final single = effectiveFiles.first;
      final fileBytes = await single.readBytes();
      uploadedBytes.add(fileBytes);
      response = await _authService.authenticatedPostMultipart(
        _documentsPath,
        fields: fields,
        fileName: single.name,
        mimeType: single.mimeType,
        fileBytes: fileBytes,
        requestTimeout: ApiTimeoutPolicy.upload,
      );
    } else {
      final multipartFiles = <ApiMultipartFile>[];
      for (final f in effectiveFiles) {
        final bytes = await f.readBytes();
        uploadedBytes.add(bytes);
        multipartFiles.add(
          ApiMultipartFile(
            field: 'files',
            fileName: f.name,
            mimeType: f.mimeType,
            bytes: bytes,
          ),
        );
      }
      response = await _authService.authenticatedPostMultipartFiles(
        _documentsPath,
        fields: fields,
        files: multipartFiles,
        requestTimeout: ApiTimeoutPolicy.upload,
      );
    }

    final document = _parseDocument(_dataOf(response)['document']);
    if (authGeneration != _authGeneration) return document;
    _cacheUploadedDocumentBytes(document, uploadedBytes);
    _documents = [
      document,
      ..._documents.where((value) => value.id != document.id),
    ];
    _summary = _summary.adding(document);
    _hasLoadedDocuments = true;
    _errorMessage = null;
    notifyListeners();
    return document;
  }

  void _cacheUploadedDocumentBytes(
    DocumentRecord document,
    List<Uint8List> uploadedBytes,
  ) {
    if (uploadedBytes.isEmpty) return;
    _putInContentCache(document.id, uploadedBytes.first);
    final attachments = document.effectiveAttachments;
    for (var i = 0; i < attachments.length && i < uploadedBytes.length; i++) {
      _putInContentCache(
        '${document.id}:${attachments[i].id}',
        uploadedBytes[i],
      );
    }
  }

  Future<void> seedUploadedContent(
    DocumentRecord document,
    List<PickedDocument> files,
  ) async {
    if (files.isEmpty) return;
    final uploadedBytes = <Uint8List>[];
    for (final file in files) {
      try {
        uploadedBytes.add(await file.readBytes());
      } catch (_) {
        return;
      }
    }
    _cacheUploadedDocumentBytes(document, uploadedBytes);
  }

  void seedDocumentOcr(String documentId, DocumentOcrResult ocr) {
    _ocrResults[documentId] = ocr;
    notifyListeners();
  }

  Future<void> delete(String documentId) async {
    final authGeneration = _authGeneration;
    final existing = _documents
        .where((value) => value.id == documentId)
        .firstOrNull;
    await _authService.authenticatedDeleteJson('$_documentsPath/$documentId');
    if (authGeneration != _authGeneration) return;
    _documents = _documents
        .where((document) => document.id != documentId)
        .toList(growable: false);
    _ocrResults.remove(documentId);
    final removedPrimary = _contentCache.remove(documentId);
    if (removedPrimary != null) {
      _currentCachedBytes -= removedPrimary.length;
    }
    final attachmentKeys = _contentCache.keys
        .where((key) => key.startsWith('$documentId:'))
        .toList(growable: false);
    for (final key in attachmentKeys) {
      final removed = _contentCache.remove(key);
      if (removed != null) {
        _currentCachedBytes -= removed.length;
      }
    }
    if (existing != null) _summary = _summary.removing(existing);
    _hasLoadedDocuments = true;
    notifyListeners();
  }

  Future<DocumentOcrResult> loadOcr(String documentId) async {
    final authGeneration = _authGeneration;
    final existing = _ocrResults[documentId];
    final response = await _authService.authenticatedGetJson(
      '$_documentsPath/$documentId/ocr',
    );
    final parsed = _parseOcr(_dataOf(response)['ocr']);
    final result =
        (parsed.status == DocumentOcrStatus.notProcessed &&
            existing != null &&
            existing.isReady)
        ? existing
        : parsed;
    if (authGeneration == _authGeneration) {
      _ocrResults[documentId] = result;
      notifyListeners();
    }
    return result;
  }

  Future<DocumentOcrResult> previewOcr(dynamic fileOrFiles) async {
    final List<PickedDocument> effectiveFiles =
        fileOrFiles is List<PickedDocument>
        ? fileOrFiles
        : fileOrFiles is PickedDocument
        ? [fileOrFiles]
        : const <PickedDocument>[];

    if (effectiveFiles.isEmpty) {
      throw const ApiException(
        code: 'VALIDATION_ERROR',
        message: 'At least one file is required.',
        statusCode: 400,
      );
    }

    final authGeneration = _authGeneration;
    final Map<String, dynamic> response;
    if (effectiveFiles.length == 1) {
      final single = effectiveFiles.first;
      final fileBytes = await single.readBytes();
      response = await _authService.authenticatedPostMultipart(
        '$_documentsPath/ocr-preview',
        fields: const {},
        fileName: single.name,
        mimeType: single.mimeType,
        fileBytes: fileBytes,
        requestTimeout: ocrPreviewTimeout,
      );
    } else {
      final multipartFiles = <ApiMultipartFile>[];
      for (final f in effectiveFiles) {
        multipartFiles.add(
          ApiMultipartFile(
            field: 'files',
            fileName: f.name,
            mimeType: f.mimeType,
            bytes: await f.readBytes(),
          ),
        );
      }
      response = await _authService.authenticatedPostMultipartFiles(
        '$_documentsPath/ocr-preview',
        fields: const {},
        files: multipartFiles,
        requestTimeout: ocrPreviewTimeout,
      );
    }

    if (authGeneration != _authGeneration) {
      throw const ApiException(
        code: 'UNAUTHORIZED',
        message: 'Your session has changed. Please try again.',
        statusCode: 401,
      );
    }
    return _parseOcr(_dataOf(response)['ocr']);
  }

  Future<DocumentOcrResult> extractText(String documentId) async {
    if (_extractingDocumentIds.contains(documentId)) {
      throw const ApiException(
        code: 'OCR_ALREADY_PROCESSING',
        message: 'Text extraction is already in progress for this document.',
        statusCode: 409,
      );
    }
    final authGeneration = _authGeneration;
    _extractingDocumentIds.add(documentId);
    notifyListeners();
    try {
      return await _ocrCoordinator.runGuarded(() async {
        final response = await _authService.authenticatedPostJsonWithTimeout(
          '$_documentsPath/$documentId/ocr',
          body: const {},
          timeout: ocrRequestTimeout,
        );
        final result = _parseOcr(_dataOf(response)['ocr']);
        if (authGeneration == _authGeneration) {
          _ocrResults[documentId] = result;
        }
        return result;
      });
    } finally {
      _extractingDocumentIds.remove(documentId);
      notifyListeners();
    }
  }

  Future<DocumentOcrResult> saveReviewedText(
    String documentId,
    String reviewedText,
  ) async {
    final authGeneration = _authGeneration;
    final response = await _authService.authenticatedPatchJson(
      '$_documentsPath/$documentId/ocr',
      body: {'reviewedText': reviewedText},
    );
    final result = _parseOcr(_dataOf(response)['ocr']);
    if (authGeneration == _authGeneration) {
      _ocrResults[documentId] = result;
      notifyListeners();
    }
    return result;
  }

  Future<DocumentRecord> updateDocumentMetadata(
    String documentId, {
    String? categoryKey,
    String? folderKey,
    String? title,
    DateTime? documentDate,
    String? description,
    String? reflection,
  }) async {
    final body = <String, dynamic>{};
    if (categoryKey != null) body['categoryKey'] = categoryKey;
    if (folderKey != null) body['folderKey'] = folderKey;
    if (title != null) body['title'] = title;
    if (documentDate != null) {
      body['documentDate'] = _dateOnly(documentDate);
    }
    if (description != null) body['description'] = description;
    if (reflection != null) body['reflection'] = reflection;

    final response = await _authService.authenticatedPatchJson(
      '$_documentsPath/$documentId',
      body: body,
    );
    final updated = _parseDocument(_dataOf(response)['document']);

    final index = _documents.indexWhere((d) => d.id == documentId);
    if (index != -1) {
      final list = List<DocumentRecord>.from(_documents);
      list[index] = updated;
      _documents = list;
      notifyListeners();
    }
    return updated;
  }

  Future<CompiledAnalysisResult> analyzeCompiledDocument(
    PickedDocument file,
  ) async {
    return _ocrCoordinator.runGuarded(() async {
      final fileBytes = await file.readBytes();
      try {
        final response = await _authService.authenticatedPostMultipart(
          '$_documentsPath/compiled/analyze',
          fields: const {},
          fileName: file.name,
          mimeType: file.mimeType,
          fileBytes: fileBytes,
          requestTimeout: compiledAnalysisTimeout,
        );
        return CompiledAnalysisResult.fromJson(_dataOf(response));
      } finally {
        file.releaseBytes();
      }
    });
  }

  Future<List<DocumentRecord>> splitCompiledDocument({
    required String sessionId,
    required String idempotencyKey,
    required List<CompiledSplitSegment> segments,
  }) async {
    final response = await _authService.authenticatedPostJsonWithTimeout(
      '$_documentsPath/compiled/split',
      body: {
        'sessionId': sessionId,
        'idempotencyKey': idempotencyKey,
        'segments': segments.map((s) => s.toJson()).toList(),
      },
      timeout: const Duration(seconds: 90),
    );
    final data = _dataOf(response);
    final docsRaw = data['documents'];
    if (docsRaw is! List) throw _invalidResponse();
    final docs = docsRaw.map(_parseDocument).toList();

    await load(force: true);
    return docs;
  }

  Future<bool> cancelCompiledSession(String sessionId) async {
    try {
      final response = await _authService.authenticatedPostJson(
        '$_documentsPath/compiled/cancel',
        body: {'sessionId': sessionId},
      );
      return _dataOf(response)['cancelled'] == true;
    } catch (_) {
      return false;
    }
  }

  Uint8List? getCachedContent(String documentId, {String? attachmentId}) {
    final cacheKey = attachmentId != null && attachmentId.isNotEmpty
        ? '$documentId:$attachmentId'
        : documentId;
    return _contentCache[cacheKey];
  }

  Future<Uint8List> getDocumentContent(
    String documentId, {
    String? attachmentId,
  }) async {
    final cacheKey = attachmentId != null && attachmentId.isNotEmpty
        ? '$documentId:$attachmentId'
        : documentId;

    final cached = _contentCache[cacheKey];
    if (cached != null) return cached;

    final inFlight = _inFlightContentRequests[cacheKey];
    if (inFlight != null) return inFlight;

    final path = attachmentId != null && attachmentId.isNotEmpty
        ? '$_documentsPath/$documentId/attachments/$attachmentId/content'
        : '$_documentsPath/$documentId/content';

    final request = () async {
      try {
        final bytes = await _authService.authenticatedGetBytes(path);
        _putInContentCache(cacheKey, bytes);
        return bytes;
      } finally {
        _inFlightContentRequests.remove(cacheKey);
      }
    }();

    _inFlightContentRequests[cacheKey] = request;
    return request;
  }

  @visibleForTesting
  void setCachedContent(
    String documentId,
    Uint8List bytes, {
    String? attachmentId,
  }) {
    final cacheKey = attachmentId != null && attachmentId.isNotEmpty
        ? '$documentId:$attachmentId'
        : documentId;
    _putInContentCache(cacheKey, bytes);
  }

  void _putInContentCache(String key, Uint8List bytes) {
    if (bytes.length > maxCachedBytes) {
      // Single payload exceeds the total cache ceiling; avoid caching.
      return;
    }

    if (_contentCache.containsKey(key)) {
      final old = _contentCache.remove(key);
      if (old != null) {
        _currentCachedBytes -= old.length;
      }
    }

    while (_contentCache.isNotEmpty &&
        (_contentCache.length >= maxCachedDocuments ||
            (_currentCachedBytes + bytes.length) > maxCachedBytes)) {
      final oldestKey = _contentCache.keys.first;
      final evicted = _contentCache.remove(oldestKey);
      if (evicted != null) {
        _currentCachedBytes -= evicted.length;
      }
    }

    _contentCache[key] = bytes;
    _currentCachedBytes += bytes.length;
  }

  Uint8List? getCachedThumbnail(String documentId, {String? attachmentId}) {
    final cacheKey = attachmentId != null && attachmentId.isNotEmpty
        ? '$documentId:$attachmentId'
        : documentId;
    return _thumbnailCache[cacheKey];
  }

  Future<Uint8List?> getPdfThumbnail(
    String documentId, {
    String? attachmentId,
    double dpi = 72.0,
  }) async {
    final cacheKey = attachmentId != null && attachmentId.isNotEmpty
        ? '$documentId:$attachmentId'
        : documentId;

    final cached = _thumbnailCache[cacheKey];
    if (cached != null) return cached;

    final inFlight = _inFlightThumbnailRequests[cacheKey];
    if (inFlight != null) return inFlight;

    final request = () async {
      try {
        final pdfBytes = await getDocumentContent(
          documentId,
          attachmentId: attachmentId,
        );
        final thumb = await _pdfThumbnailRenderer.renderPage1(
          pdfBytes,
          dpi: dpi,
        );
        if (thumb != null) {
          _putInThumbnailCache(cacheKey, thumb);
        }
        return thumb;
      } catch (_) {
        return null;
      } finally {
        _inFlightThumbnailRequests.remove(cacheKey);
      }
    }();

    _inFlightThumbnailRequests[cacheKey] = request;
    return request;
  }

  @visibleForTesting
  void setCachedThumbnail(
    String documentId,
    Uint8List bytes, {
    String? attachmentId,
  }) {
    final cacheKey = attachmentId != null && attachmentId.isNotEmpty
        ? '$documentId:$attachmentId'
        : documentId;
    _putInThumbnailCache(cacheKey, bytes);
  }

  void _putInThumbnailCache(String key, Uint8List bytes) {
    if (bytes.length > maxCachedThumbnailBytes) {
      return;
    }

    if (_thumbnailCache.containsKey(key)) {
      final old = _thumbnailCache.remove(key);
      if (old != null) {
        _currentCachedThumbnailBytes -= old.length;
      }
    }

    while (_thumbnailCache.isNotEmpty &&
        (_thumbnailCache.length >= maxCachedThumbnails ||
            (_currentCachedThumbnailBytes + bytes.length) >
                maxCachedThumbnailBytes)) {
      final oldestKey = _thumbnailCache.keys.first;
      final evicted = _thumbnailCache.remove(oldestKey);
      if (evicted != null) {
        _currentCachedThumbnailBytes -= evicted.length;
      }
    }

    _thumbnailCache[key] = bytes;
    _currentCachedThumbnailBytes += bytes.length;
  }

  Future<void> _loadDocuments(int authGeneration) async {
    final response = await _authService.authenticatedGetJson(_documentsPath);
    final data = _dataOf(response);
    final values = data['documents'];
    final rawSummary = data['summary'];
    if (values is! List || rawSummary is! Map<String, dynamic>) {
      throw _invalidResponse();
    }
    final documents = values.map(_parseDocument).toList(growable: false);
    late final DocumentSummary summary;
    try {
      summary = DocumentSummary.fromJson(rawSummary);
    } catch (_) {
      throw _invalidResponse();
    }
    if (authGeneration != _authGeneration) return;
    _documents = documents;
    _summary = summary;
    _hasLoadedDocuments = true;
  }

  Future<void> _loadCategories(int authGeneration) async {
    final response = await _authService.authenticatedGetJson(
      '$_documentsPath/categories',
    );
    final values = _dataOf(response)['categories'];
    if (values is! List) throw _invalidResponse();
    try {
      final categories = values
          .map((value) {
            if (value is! Map<String, dynamic>) throw const FormatException();
            return DocumentCategory.fromJson(value);
          })
          .toList(growable: false);
      if (authGeneration != _authGeneration) return;
      _categories = categories;
    } catch (_) {
      throw _invalidResponse();
    }
    _hasLoadedCategories = true;
  }

  void _handleAuthChanged() {
    final userId = _authService.user?.id;
    if (userId == _authenticatedUserId) return;
    _authenticatedUserId = userId;
    _authGeneration++;
    _loadOperation++;
    _documents = const [];
    _categories = const [];
    _summary = DocumentSummary.empty;
    _hasLoadedDocuments = false;
    _hasLoadedCategories = false;
    _isLoading = false;
    _errorMessage = null;
    _ocrResults.clear();
    _extractingDocumentIds.clear();
    _contentCache.clear();
    _currentCachedBytes = 0;
    _inFlightContentRequests.clear();
    _thumbnailCache.clear();
    _currentCachedThumbnailBytes = 0;
    _inFlightThumbnailRequests.clear();
    notifyListeners();
  }

  static Map<String, dynamic> _dataOf(Map<String, dynamic> envelope) {
    final data = envelope['data'];
    if (data is Map<String, dynamic>) return data;
    throw _invalidResponse();
  }

  static DocumentRecord _parseDocument(Object? value) {
    if (value is! Map<String, dynamic>) throw _invalidResponse();
    try {
      return DocumentRecord.fromJson(value);
    } catch (_) {
      throw _invalidResponse();
    }
  }

  static DocumentOcrResult _parseOcr(Object? value) {
    if (value is! Map<String, dynamic>) throw _invalidResponse();
    try {
      return DocumentOcrResult.fromJson(value);
    } catch (_) {
      throw _invalidResponse();
    }
  }

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static ApiException _invalidResponse() => const ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The server returned an invalid response.',
  );

  @override
  void dispose() {
    _authService.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
