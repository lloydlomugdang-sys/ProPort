import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'auth_service.dart';
import 'document_models.dart';

class DocumentService extends ChangeNotifier {
  DocumentService({required AuthService authService})
    : _authService = authService,
      _authenticatedUserId = authService.user?.id {
    _authService.addListener(_handleAuthChanged);
  }

  static const maxUploadBytes = 15 * 1024 * 1024;
  static const ocrRequestTimeout = Duration(seconds: 60);
  // Preview includes upload, a possible cold start and the backend's bounded
  // 45-second OCR job plus bounded Gemini analysis (at most 30 seconds).
  // Keep ordinary API requests on their existing timeout.
  static const ocrPreviewTimeout = Duration(seconds: 120);
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
  int _authGeneration = 0;
  int _loadOperation = 0;

  List<DocumentRecord> get documents => List.unmodifiable(_documents);
  List<DocumentCategory> get categories => List.unmodifiable(_categories);
  DocumentSummary get summary => _summary;
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
    try {
      if (force || !_hasLoadedCategories) {
        await _loadCategories(authGeneration);
      }
      if (authGeneration != _authGeneration) return;
      if (force || !_hasLoadedDocuments) {
        await _loadDocuments(authGeneration);
      }
    } on ApiException catch (error) {
      if (authGeneration == _authGeneration) {
        _errorMessage = error.message;
      }
      rethrow;
    } catch (_) {
      if (authGeneration == _authGeneration) {
        _errorMessage = 'Unable to load documents. Please try again.';
      }
      rethrow;
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

    final Map<String, dynamic> response;
    if (effectiveFiles.length == 1) {
      final single = effectiveFiles.first;
      response = await _authService.authenticatedPostMultipart(
        _documentsPath,
        fields: fields,
        fileName: single.name,
        mimeType: single.mimeType,
        fileBytes: single.bytes,
      );
    } else {
      final multipartFiles = effectiveFiles
          .map(
            (f) => ApiMultipartFile(
              field: 'files',
              fileName: f.name,
              mimeType: f.mimeType,
              bytes: f.bytes,
            ),
          )
          .toList(growable: false);
      response = await _authService.authenticatedPostMultipartFiles(
        _documentsPath,
        fields: fields,
        files: multipartFiles,
      );
    }

    final document = _parseDocument(_dataOf(response)['document']);
    if (authGeneration != _authGeneration) return document;
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
    if (existing != null) _summary = _summary.removing(existing);
    _hasLoadedDocuments = true;
    notifyListeners();
  }

  Future<DocumentOcrResult> loadOcr(String documentId) async {
    final authGeneration = _authGeneration;
    final response = await _authService.authenticatedGetJson(
      '$_documentsPath/$documentId/ocr',
    );
    final result = _parseOcr(_dataOf(response)['ocr']);
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
      response = await _authService.authenticatedPostMultipart(
        '$_documentsPath/ocr-preview',
        fields: const {},
        fileName: single.name,
        mimeType: single.mimeType,
        fileBytes: single.bytes,
        requestTimeout: ocrPreviewTimeout,
      );
    } else {
      final multipartFiles = effectiveFiles
          .map(
            (f) => ApiMultipartFile(
              field: 'files',
              fileName: f.name,
              mimeType: f.mimeType,
              bytes: f.bytes,
            ),
          )
          .toList(growable: false);
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
