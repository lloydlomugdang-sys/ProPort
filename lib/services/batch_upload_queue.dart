import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../screens/files/models/batch_upload_item.dart';
import 'api_client.dart';
import 'document_models.dart';
import 'document_service.dart';

class BatchUploadQueue extends ChangeNotifier {
  BatchUploadQueue({
    required DocumentService documentService,
    int? maxConcurrent,
    int? maxConcurrentUploads,
    this.maxBatchSize = 20,
    this.maxRetries = 3,
  }) : maxConcurrentUploads = maxConcurrentUploads ?? maxConcurrent ?? 2,
       _documentService = documentService;

  final DocumentService _documentService;
  final int maxConcurrentUploads;
  final int maxBatchSize;
  final int maxRetries;

  // Compatibility alias for maxConcurrent
  int get maxConcurrent => maxConcurrentUploads;

  final List<BatchUploadItem> _items = [];
  int _activeUploadWorkers = 0;
  int _activeOcrWorkers = 0;
  bool _isDisposed = false;
  bool _isProcessingBatch = false;
  Completer<int>? _batchCompleter;
  Future<void>? _preparation;

  List<BatchUploadItem> get items => List.unmodifiable(_items);
  int get totalCount => _items.length;
  int get queuedCount =>
      _items.where((i) => i.status == BatchItemStatus.queued).length;
  int get uploadingCount =>
      _items.where((i) => i.status == BatchItemStatus.uploading).length;
  int get uploadedCount => _items.where((i) => i.isUploaded).length;
  int get waitingForOcrCount =>
      _items.where((i) => i.status == BatchItemStatus.waitingForOcr).length;
  int get extractingCount =>
      _items.where((i) => i.status == BatchItemStatus.extracting).length;
  int get completedCount =>
      _items.where((i) => i.status == BatchItemStatus.completed).length;
  int get savedCount => completedCount;
  int get failedCount => _items.where((i) => i.isFailed).length;
  int get processingCount => _items.where((i) => i.isProcessing).length;
  int get readyCount => _items
      .where((i) => i.status == BatchItemStatus.queued || i.isCompleted)
      .length;

  int get validToSaveCount => _items
      .where(
        (i) =>
            i.isValidForUpload &&
            (i.status == BatchItemStatus.queued || i.isFailed),
      )
      .length;

  bool get isAllProcessed => _items.every((i) => !i.isProcessing);
  bool get isAllCompleted =>
      _items.isNotEmpty && _items.every((i) => i.isCompleted);
  bool get isAllSaved => isAllCompleted;
  bool get isProcessingBatch => _isProcessingBatch;
  bool get isSavingAll => _isProcessingBatch;

  bool get hasActiveUploads =>
      _activeUploadWorkers > 0 ||
      _items.any((i) => i.status == BatchItemStatus.uploading);

  bool get hasPendingUploads => _items.any(
    (i) =>
        i.status == BatchItemStatus.queued ||
        i.status == BatchItemStatus.uploading,
  );

  // All normal selections, including one file, use this same serial processor.
  // The existing preview endpoint extracts locally then sends TEXT ONLY to AI.
  // No document is saved until the user confirms its metadata.
  Future<void> prepare() => _preparation ??= _prepareItems();

  /// Append independent files, preserving IDs, edits and saved items. Use the
  /// same serial preview/OCR pipeline, only for newly added items.
  void append(List<PickedDocument> files) {
    if (_isDisposed || isSavingAll || hasActiveUploads) return;
    validateFiles(files, remaining: maxBatchSize - totalCount);
    if (files.isEmpty) return;
    final added = [
      for (var i = 0; i < files.length; i++)
        BatchUploadItem(
          id: 'batch_item_${DateTime.now().microsecondsSinceEpoch}_${totalCount + i}',
          file: files[i],
          title: _cleanFilename(files[i].name),
          documentDate: DateTime.now(),
        ),
    ];
    final previous = prepare();
    _items.addAll(added);
    _preparation = previous.then((_) async {
      for (final item in added) {
        if (_isDisposed) return;
        await prepareItem(item.id);
      }
    });
    notifyListeners();
  }

  static void validateFiles(List<PickedDocument> files, {int remaining = 20}) {
    if (files.length > remaining) {
      throw ApiException(
        code: 'VALIDATION_ERROR',
        message: 'You can add up to $remaining more documents (20 total).',
      );
    }
    for (final file in files) {
      if (!file.hasSupportedUploadType) {
        throw const ApiException(
          code: 'VALIDATION_ERROR',
          message: 'Please select a PDF, JPG, JPEG, or PNG file.',
        );
      }
      if (file.sizeBytes > DocumentService.maxUploadBytes) {
        throw const ApiException(
          code: 'VALIDATION_ERROR',
          message: 'The selected file exceeds the 15 MB upload limit.',
        );
      }
    }
  }

  Future<void> _prepareItems() async {
    for (final item in List<BatchUploadItem>.of(_items)) {
      if (_isDisposed) return;
      await prepareItem(item.id);
    }
  }

  Future<void> prepareItem(String itemId) async {
    var index = _items.indexWhere((item) => item.id == itemId);
    if (_isDisposed ||
        index == -1 ||
        _items[index].isProcessing ||
        _items[index].isUploaded) {
      return;
    }
    final file = _items[index].file;
    _items[index] = _items[index].copyWith(
      isPreviewing: true,
      clearPreviewError: true,
    );
    notifyListeners();
    try {
      final result = await _documentService.ocrCoordinator.runGuarded(
        () => _documentService.previewOcr(file),
      );
      if (!result.isReady || (result.rawText?.trim().isEmpty ?? true)) {
        throw const ApiException(
          code: 'OCR_FAILED',
          message: 'No readable text was found in this document.',
        );
      }
      index = _items.indexWhere((item) => item.id == itemId);
      if (_isDisposed || index == -1) return;
      // Read the latest item after awaiting: manual edits win over late results.
      final existing = _items[index];
      final suggestions = result.metadataSuggestions;
      final apply = !existing.isManualCategory;
      _items[index] = existing.copyWith(
        previewResult: result,
        rawText: result.rawText,
        reviewedText: result.reviewedText,
        categoryKey: apply ? suggestions?.categoryKey : null,
        folderKey: apply ? suggestions?.folderKey : null,
        clearFolder:
            apply &&
            suggestions?.categoryKey != null &&
            suggestions!.categoryKey != existing.categoryKey &&
            suggestions.folderKey == null,
        title: apply ? suggestions?.title : null,
        documentDate: apply ? suggestions?.documentDate : null,
        description: apply ? suggestions?.description : null,
        descriptionSource: apply && suggestions?.description != null ? 'suggested' : null,
        confidence: suggestions?.confidence,
        isAutoCategorized: apply && suggestions?.categoryKey != null,
      );
    } catch (error) {
      index = _items.indexWhere((item) => item.id == itemId);
      if (!_isDisposed && index != -1) {
        _items[index] = _items[index].copyWith(
          previewError: error is ApiException
              ? error.message
              : 'Text extraction failed. Retry reading or enter details manually.',
        );
      }
    } finally {
      // Keep large file buffers lazy while the user reviews metadata.
      file.releaseBytes();
      index = _items.indexWhere((item) => item.id == itemId);
      if (!_isDisposed && index != -1) {
        _items[index] = _items[index].copyWith(isPreviewing: false);
        notifyListeners();
        _drainUploadQueue();
      }
    }
  }

  void initialize(
    List<PickedDocument> files, {
    String? defaultCategoryKey,
    String? defaultFolderKey,
    bool autoStart = false,
  }) {
    if (files.length > maxBatchSize) {
      throw ArgumentError(
        'You can select up to $maxBatchSize documents. Selected: ${files.length}.',
      );
    }
    _items.clear();
    _preparation = null;
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      _items.add(
        BatchUploadItem(
          id: 'batch_item_${DateTime.now().microsecondsSinceEpoch}_$i',
          file: file,
          status: BatchItemStatus.queued,
          title: _cleanFilename(file.name),
          categoryKey: defaultCategoryKey,
          folderKey: defaultFolderKey,
          documentDate: DateTime.now(),
          isManualCategory: false,
          isAutoCategorized: false,
        ),
      );
    }
    notifyListeners();
    if (autoStart) {
      startProcessing();
    }
  }

  Future<int> startProcessing() async {
    // Do not let Upload All race unprocessed preview items into persistence.
    await _preparation;
    if (_isDisposed) return completedCount;
    if (_isProcessingBatch) {
      return _batchCompleter?.future ?? Future.value(completedCount);
    }
    _isProcessingBatch = true;
    _batchCompleter = Completer<int>();
    notifyListeners();

    _drainUploadQueue();
    _checkBatchCompletion();
    return _batchCompleter!.future;
  }

  Future<int> saveAllValid() async {
    return startProcessing();
  }

  void _drainUploadQueue() {
    if (_isDisposed || !_isProcessingBatch) return;
    while (_activeUploadWorkers < maxConcurrentUploads) {
      final nextIndex = _items.indexWhere(
        (i) =>
            i.status == BatchItemStatus.queued &&
            !i.isPreviewing &&
            i.isValidForUpload,
      );
      if (nextIndex == -1) break;

      final item = _items[nextIndex];
      _activeUploadWorkers++;
      _uploadItem(item.id);
    }
    _checkBatchCompletion();
  }

  Future<void> _uploadItem(String itemId) async {
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index == -1 || _isDisposed) {
      _activeUploadWorkers--;
      _drainUploadQueue();
      return;
    }

    _items[index] = _items[index].copyWith(
      status: BatchItemStatus.uploading,
      errorMessage: null,
    );
    notifyListeners();

    final current = _items[index];

    // Lazy file materialization: read bytes only when upload worker starts
    try {
      await current.file.readBytes();
    } on FileSystemException catch (_) {
      if (_isDisposed) return;
      _activeUploadWorkers--;
      final curIdx = _items.indexWhere((i) => i.id == itemId);
      if (curIdx != -1) {
        _items[curIdx] = _items[curIdx].copyWith(
          status: BatchItemStatus.failed,
          errorMessage:
              'The file could not be read from device storage. Please try again.',
        );
        notifyListeners();
      }
      _drainUploadQueue();
      return;
    } catch (_) {
      if (_isDisposed) return;
      _activeUploadWorkers--;
      final curIdx = _items.indexWhere((i) => i.id == itemId);
      if (curIdx != -1) {
        _items[curIdx] = _items[curIdx].copyWith(
          status: BatchItemStatus.failed,
          errorMessage: 'Unable to access the selected file. Please try again.',
        );
        notifyListeners();
      }
      _drainUploadQueue();
      return;
    }

    try {
      final createdDoc = await _documentService.upload(
        file: current.file,
        categoryKey: current.categoryKey!,
        folderKey: current.folderKey!,
        title: current.title!.trim(),
        documentDate: current.documentDate!,
        description: current.description?.trim(),
        descriptionSource: current.descriptionSource,
        reflection: current.reflection?.trim(),
        scholastic: current.isTor ? current.scholastic : null,
      );

      // Immediately release in-memory bytes to free client RAM
      current.file.releaseBytes();

      if (_isDisposed) return;
      final curIdx = _items.indexWhere((i) => i.id == itemId);
      if (curIdx != -1) {
        final uploadedItem = _items[curIdx];
        if (uploadedItem.isOcrEligible) {
          _items[curIdx] = uploadedItem.copyWith(
            status: BatchItemStatus.waitingForOcr,
            documentId: createdDoc.id,
            errorMessage: null,
          );
        } else {
          // Unsupported or non-OCR formats complete immediately upon successful upload
          _items[curIdx] = uploadedItem.copyWith(
            status: BatchItemStatus.completed,
            documentId: createdDoc.id,
            errorMessage: null,
          );
        }
        notifyListeners();
      }
    } on ApiException catch (e) {
      current.file.releaseBytes();
      if (_isDisposed) return;
      final curIdx = _items.indexWhere((i) => i.id == itemId);
      if (curIdx != -1) {
        final errorMsg = e.statusCode == 415
            ? 'This file format is not supported for upload.'
            : e.statusCode == 413
            ? 'The file exceeds the upload limit.'
            : e.message.isNotEmpty
            ? e.message
            : 'Upload failed. Please retry.';
        _items[curIdx] = _items[curIdx].copyWith(
          status: BatchItemStatus.failed,
          errorMessage: errorMsg,
        );
        notifyListeners();
      }
    } catch (_) {
      current.file.releaseBytes();
      if (_isDisposed) return;
      final curIdx = _items.indexWhere((i) => i.id == itemId);
      if (curIdx != -1) {
        _items[curIdx] = _items[curIdx].copyWith(
          status: BatchItemStatus.failed,
          errorMessage: 'Upload failed. Please retry.',
        );
        notifyListeners();
      }
    } finally {
      _activeUploadWorkers--;
      if (!_isDisposed) {
        _drainUploadQueue();
        _drainOcrQueue();
      }
    }
  }

  void _drainOcrQueue() {
    if (_isDisposed) return;
    while (_activeOcrWorkers < 1) {
      final nextIndex = _items.indexWhere(
        (i) =>
            i.status == BatchItemStatus.waitingForOcr && i.documentId != null,
      );
      if (nextIndex == -1) break;

      final item = _items[nextIndex];
      _activeOcrWorkers++;
      _extractOcrForItem(item.id);
    }
    _checkBatchCompletion();
  }

  Future<void> _extractOcrForItem(String itemId) async {
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index == -1 || _isDisposed) {
      _activeOcrWorkers--;
      _drainOcrQueue();
      return;
    }

    _items[index] = _items[index].copyWith(
      status: BatchItemStatus.extracting,
      errorMessage: null,
    );
    notifyListeners();

    final current = _items[index];

    try {
      // Upload may already have persisted the preview OCR from its server cache.
      // Confirm it through the existing read endpoint before doing expensive OCR
      // again; cache misses still use the established extraction/retry path.
      final persisted = current.previewResult?.isReady == true
          ? await _documentService.loadOcr(current.documentId!)
          : null;
      final ocrResult =
          persisted?.isReady == true &&
              (persisted!.rawText?.trim().isNotEmpty ?? false)
          ? persisted
          : await _documentService.extractText(current.documentId!);

      if (_isDisposed) return;
      final curIdx = _items.indexWhere((i) => i.id == itemId);
      if (curIdx != -1) {
        final existing = _items[curIdx];
        // Persisted extraction must not replace the reviewed AI preview with
        // the saved-OCR endpoint's rule-only suggestions.
        final suggestions =
            existing.previewResult?.metadataSuggestions ??
            ocrResult.metadataSuggestions;
        final hasCategorySuggestion =
            suggestions != null &&
            suggestions.categoryKey != null &&
            suggestions.categoryKey!.trim().isNotEmpty;

        String? updatedCategory = existing.categoryKey;
        String? updatedFolder = existing.folderKey;
        String? updatedTitle = existing.title;
        DateTime? updatedDate = existing.documentDate;
        String? updatedDescription = existing.description;
        bool isAutoCategorized = existing.isAutoCategorized;

        if (!existing.isManualCategory && hasCategorySuggestion) {
          updatedCategory = suggestions.categoryKey;
          updatedFolder = suggestions.folderKey ?? existing.folderKey;
          if (suggestions.title != null &&
              suggestions.title!.trim().isNotEmpty) {
            updatedTitle = suggestions.title;
          }
          if (suggestions.documentDate != null) {
            updatedDate = suggestions.documentDate;
          }
          if (suggestions.description != null &&
              suggestions.description!.trim().isNotEmpty) {
            updatedDescription = suggestions.description;
          }
          isAutoCategorized = true;

          if (existing.documentId != null) {
            try {
              await _documentService.updateDocumentMetadata(
                existing.documentId!,
                categoryKey: updatedCategory,
                folderKey: updatedFolder,
                title: updatedTitle,
                documentDate: updatedDate,
                description: updatedDescription,
                descriptionSource: 'suggested',
              );
            } catch (_) {
              // Best-effort metadata sync
            }
          }
        }

        _items[curIdx] = existing.copyWith(
          status: BatchItemStatus.completed,
          rawText: existing.previewResult?.rawText ?? ocrResult.rawText,
          reviewedText:
              existing.previewResult?.reviewedText ?? ocrResult.reviewedText,
          categoryKey: updatedCategory,
          folderKey: updatedFolder,
          title: updatedTitle,
          documentDate: updatedDate,
          description: updatedDescription,
          descriptionSource: !existing.isManualCategory && hasCategorySuggestion && suggestions.description != null ? 'suggested' : existing.descriptionSource,
          confidence: suggestions?.confidence ?? existing.confidence,
          isAutoCategorized: isAutoCategorized,
          errorMessage: null,
        );
        notifyListeners();
      }
    } on ApiException catch (e) {
      if (_isDisposed) return;
      final curIdx = _items.indexWhere((i) => i.id == itemId);
      if (curIdx != -1) {
        final isBusy = e.statusCode == 503 || e.code == 'OCR_BUSY';
        final errorMsg = isBusy
            ? 'The server is busy extracting another document. Tap Retry to extract text.'
            : e.statusCode == 504
            ? 'Text extraction timed out. Tap Retry to try again.'
            : e.statusCode == 422
            ? 'No readable text was found in this document.'
            : e.message.isNotEmpty
            ? e.message
            : 'Text extraction failed. Tap Retry to try again.';

        _items[curIdx] = _items[curIdx].copyWith(
          status: BatchItemStatus.failed,
          errorMessage: errorMsg,
        );
        notifyListeners();
      }
    } catch (_) {
      if (_isDisposed) return;
      final curIdx = _items.indexWhere((i) => i.id == itemId);
      if (curIdx != -1) {
        _items[curIdx] = _items[curIdx].copyWith(
          status: BatchItemStatus.failed,
          errorMessage: 'Text extraction failed. Tap Retry to try again.',
        );
        notifyListeners();
      }
    } finally {
      _activeOcrWorkers--;
      if (!_isDisposed) {
        _drainOcrQueue();
      }
    }
  }

  void _checkBatchCompletion() {
    if (_isDisposed) return;
    if (_isProcessingBatch && isAllProcessed) {
      _isProcessingBatch = false;
      if (_batchCompleter != null && !_batchCompleter!.isCompleted) {
        _batchCompleter!.complete(completedCount);
      }
      notifyListeners();
    }
  }

  void retry(String itemId) {
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index == -1 || _items[index].isProcessing) return;

    final item = _items[index];

    // If documentId exists, upload already succeeded!
    // NEVER re-upload or duplicate document. Retry OCR only.
    if (item.documentId != null) {
      _items[index] = item.copyWith(
        status: BatchItemStatus.waitingForOcr,
        errorMessage: null,
      );
      notifyListeners();
      _drainOcrQueue();
    } else {
      // Document upload failed earlier. Retry upload.
      _items[index] = item.copyWith(
        status: BatchItemStatus.queued,
        errorMessage: null,
      );
      notifyListeners();
      _drainUploadQueue();
    }
  }

  Future<bool> saveItem(String itemId) async {
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index == -1) return false;

    final item = _items[index];
    if (item.isProcessing || item.isCompleted) return false;

    if (item.isFailed) {
      retry(itemId);
      return true;
    }

    if (item.status == BatchItemStatus.queued && item.isValidForUpload) {
      _activeUploadWorkers++;
      await _uploadItem(itemId);
      return true;
    }

    return false;
  }

  void remove(String itemId) {
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index == -1 || _items[index].isProcessing) return;

    _items[index].file.releaseBytes();
    _items.removeAt(index);
    notifyListeners();
    _checkBatchCompletion();
  }

  void updateItemMetadata(
    String itemId, {
    String? categoryKey,
    String? folderKey,
    String? title,
    DateTime? documentDate,
    String? description,
    String? reflection,
    ScholasticDetails? scholastic,
    bool isManual = true,
  }) {
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index == -1) return;

    final current = _items[index];
    if (current.isProcessing && !current.isPreviewing) return;

    final updatedCat = categoryKey ?? current.categoryKey;
    final updatedFolder = folderKey ?? current.folderKey;
    final updatedTitle = title ?? current.title;
    final updatedDate = documentDate ?? current.documentDate;
    final updatedDesc = description ?? current.description;
    final descriptionSource = description != null && isManual ? 'user' : current.descriptionSource;
    final updatedRefl = reflection ?? current.reflection;

    _items[index] = current.copyWith(
      categoryKey: updatedCat,
      folderKey: updatedFolder,
      title: updatedTitle,
      documentDate: updatedDate,
      description: updatedDesc,
      descriptionSource: descriptionSource,
      reflection: updatedRefl,
      scholastic: scholastic,
      isManualCategory: isManual ? true : current.isManualCategory,
      isAutoCategorized: isManual ? false : current.isAutoCategorized,
    );
    notifyListeners();

    if (current.documentId != null) {
      _documentService
          .updateDocumentMetadata(
            current.documentId!,
            categoryKey: updatedCat,
            folderKey: updatedFolder,
            title: updatedTitle,
            documentDate: updatedDate,
            description: updatedDesc,
            descriptionSource: descriptionSource,
            reflection: updatedRefl,
            scholastic: scholastic,
          )
          .then((_) {}, onError: (_) {});
    }
  }

  static String _cleanFilename(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    final base = dotIndex != -1 ? fileName.substring(0, dotIndex) : fileName;
    final words = base.replaceAll(RegExp(r'[-_]+'), ' ').trim();
    if (words.isEmpty) return 'Document';
    return words
        .split(' ')
        .map((w) {
          if (w.isEmpty) return '';
          return w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : '');
        })
        .join(' ');
  }

  @override
  void dispose() {
    _isDisposed = true;
    for (final item in _items) {
      item.file.releaseBytes();
    }
    super.dispose();
  }
}
