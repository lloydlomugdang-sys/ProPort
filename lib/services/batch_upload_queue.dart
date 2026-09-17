import 'dart:async';
import 'package:flutter/foundation.dart';
import '../screens/files/models/batch_upload_item.dart';
import 'api_client.dart';
import 'document_models.dart';
import 'document_service.dart';

class BatchUploadQueue extends ChangeNotifier {
  BatchUploadQueue({
    required DocumentService documentService,
    this.maxConcurrent = 2,
    this.maxBatchSize = 20,
    this.maxRetries = 3,
  }) : _documentService = documentService;

  final DocumentService _documentService;
  final int maxConcurrent;
  final int maxBatchSize;
  final int maxRetries;

  final List<BatchUploadItem> _items = [];
  int _activeWorkers = 0;
  bool _isDisposed = false;
  bool _isSavingAll = false;

  List<BatchUploadItem> get items => List.unmodifiable(_items);
  int get totalCount => _items.length;
  int get readyCount => _items.where((i) => i.isReadyForReview).length;
  int get savedCount => _items.where((i) => i.isSaved).length;
  int get failedCount => _items.where((i) => i.isFailed).length;
  int get processingCount => _items.where((i) => i.isProcessing).length;
  int get validToSaveCount => _items
      .where((i) => i.isValidForSave && (i.isReadyForReview || i.isFailed))
      .length;
  bool get isAllProcessed => _items.every((i) => !i.isProcessing);
  bool get isAllSaved => _items.isNotEmpty && _items.every((i) => i.isSaved);
  bool get isSavingAll => _isSavingAll;

  void initialize(List<PickedDocument> files) {
    if (files.length > maxBatchSize) {
      throw ArgumentError(
        'A batch cannot exceed $maxBatchSize documents. Selected: ${files.length}',
      );
    }
    _items.clear();
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      _items.add(
        BatchUploadItem(
          id: 'batch_item_${DateTime.now().microsecondsSinceEpoch}_$i',
          file: file,
          status: BatchItemStatus.waiting,
        ),
      );
    }
    notifyListeners();
    _drainQueue();
  }

  void _drainQueue() {
    if (_isDisposed) return;
    while (_activeWorkers < maxConcurrent) {
      final nextIndex = _items.indexWhere(
        (i) => i.status == BatchItemStatus.waiting,
      );
      if (nextIndex == -1) break;

      final item = _items[nextIndex];
      _activeWorkers++;
      _processItem(item.id);
    }
  }

  Future<void> _processItem(String itemId) async {
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index == -1 || _isDisposed) {
      _activeWorkers--;
      _drainQueue();
      return;
    }

    // Step 1: Text extraction
    _items[index] = _items[index].copyWith(
      status: BatchItemStatus.extractingText,
      errorMessage: null,
    );
    notifyListeners();

    try {
      // Step 2: Categorization & OCR via backend preview
      // Transition to aiCategorizing briefly or keep extracting
      final item = _items[index];
      final ocrResult = await _documentService.previewOcr(item.file);

      if (_isDisposed) return;
      final curIdx = _items.indexWhere((i) => i.id == itemId);
      if (curIdx == -1) return;

      final current = _items[curIdx];
      final suggestions = ocrResult.metadataSuggestions;

      // Extract suggested fields, preserving any user manual edits
      final suggestedTitle =
          suggestions?.title ?? _cleanFilename(current.fileName);
      final suggestedDate = suggestions?.documentDate ?? DateTime.now();
      final suggestedCategory = suggestions?.categoryKey;
      final suggestedFolder = suggestions?.folderKey;
      final suggestedDescription = suggestions?.description;
      final confidence =
          suggestions?.confidence ??
          (suggestedCategory != null ? 'medium' : 'low');

      _items[curIdx] = current.copyWith(
        status: BatchItemStatus.readyForReview,
        rawText: ocrResult.rawText,
        reviewedText: ocrResult.reviewedText,
        title: current.title ?? suggestedTitle,
        documentDate: current.documentDate ?? suggestedDate,
        categoryKey: current.categoryKey ?? suggestedCategory,
        folderKey: current.folderKey ?? suggestedFolder,
        description: current.description ?? suggestedDescription,
        confidence: current.confidence ?? confidence,
      );
    } on ApiException catch (e) {
      if (_isDisposed) return;
      final curIdx = _items.indexWhere((i) => i.id == itemId);
      if (curIdx != -1) {
        final current = _items[curIdx];
        if (e.statusCode == 429 && current.retryCount < maxRetries) {
          // Graceful 429 retry with exponential backoff
          final delayMs = 500 * (1 << current.retryCount);
          _items[curIdx] = current.copyWith(
            status: BatchItemStatus.waiting,
            retryCount: current.retryCount + 1,
            errorMessage: 'Rate limit encountered; retrying...',
          );
          notifyListeners();
          await Future.delayed(Duration(milliseconds: delayMs));
        } else {
          _items[curIdx] = current.copyWith(
            status: BatchItemStatus.failed,
            errorMessage: e.statusCode == 429
                ? 'Rate limit exceeded. Please retry.'
                : e.message,
          );
        }
      }
    } catch (_) {
      if (_isDisposed) return;
      final curIdx = _items.indexWhere((i) => i.id == itemId);
      if (curIdx != -1) {
        _items[curIdx] = _items[curIdx].copyWith(
          status: BatchItemStatus.failed,
          errorMessage: 'Unable to process document. Please retry.',
        );
      }
    } finally {
      _activeWorkers--;
      if (!_isDisposed) {
        notifyListeners();
        _drainQueue();
      }
    }
  }

  void retry(String itemId) {
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index == -1 || _items[index].isProcessing) return;

    _items[index] = _items[index].copyWith(
      status: BatchItemStatus.waiting,
      errorMessage: null,
    );
    notifyListeners();
    _drainQueue();
  }

  void remove(String itemId) {
    _items.removeWhere((i) => i.id == itemId);
    notifyListeners();
    _drainQueue();
  }

  void updateItemMetadata(
    String itemId, {
    String? categoryKey,
    String? folderKey,
    String? title,
    DateTime? documentDate,
    String? description,
    String? reflection,
  }) {
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index == -1) return;

    final current = _items[index];
    _items[index] = current.copyWith(
      categoryKey: categoryKey ?? current.categoryKey,
      folderKey: folderKey ?? current.folderKey,
      title: title ?? current.title,
      documentDate: documentDate ?? current.documentDate,
      description: description ?? current.description,
      reflection: reflection ?? current.reflection,
    );
    notifyListeners();
  }

  Future<bool> saveItem(String itemId) async {
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index == -1) return false;

    final item = _items[index];
    if (!item.isValidForSave || item.isProcessing || item.isSaved) {
      return false;
    }

    _items[index] = item.copyWith(
      status: BatchItemStatus.uploading,
      errorMessage: null,
    );
    notifyListeners();

    try {
      await _documentService.upload(
        file: item.file,
        categoryKey: item.categoryKey!,
        folderKey: item.folderKey!,
        title: item.title!,
        documentDate: item.documentDate!,
        description: item.description,
        reflection: item.reflection,
      );

      final curIdx = _items.indexWhere((i) => i.id == itemId);
      if (curIdx != -1) {
        _items[curIdx] = _items[curIdx].copyWith(
          status: BatchItemStatus.saved,
          errorMessage: null,
        );
        notifyListeners();
      }
      return true;
    } on ApiException catch (e) {
      final curIdx = _items.indexWhere((i) => i.id == itemId);
      if (curIdx != -1) {
        _items[curIdx] = _items[curIdx].copyWith(
          status: BatchItemStatus.failed,
          errorMessage: e.message,
        );
        notifyListeners();
      }
      return false;
    } catch (_) {
      final curIdx = _items.indexWhere((i) => i.id == itemId);
      if (curIdx != -1) {
        _items[curIdx] = _items[curIdx].copyWith(
          status: BatchItemStatus.failed,
          errorMessage: 'Upload failed. Please retry.',
        );
        notifyListeners();
      }
      return false;
    }
  }

  Future<int> saveAllValid() async {
    if (_isSavingAll) return 0;
    _isSavingAll = true;
    notifyListeners();

    int successCount = 0;
    try {
      final candidateIds = _items
          .where((i) => i.isValidForSave && (i.isReadyForReview || i.isFailed))
          .map((i) => i.id)
          .toList();

      final pool = <Future<void>>{};
      for (final id in candidateIds) {
        if (_isDisposed) break;
        late final Future<void> task;
        task = saveItem(id).then((success) {
          if (success) successCount++;
          pool.remove(task);
        });
        pool.add(task);

        if (pool.length >= maxConcurrent) {
          await Future.any(pool);
        }
      }
      if (pool.isNotEmpty) {
        await Future.wait(pool);
      }
    } finally {
      _isSavingAll = false;
      notifyListeners();
    }
    return successCount;
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
    super.dispose();
  }
}
