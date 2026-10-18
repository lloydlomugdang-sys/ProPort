import 'package:proport_app/services/document_models.dart';

enum BatchItemStatus {
  queued,
  uploading,
  uploaded,
  waitingForOcr,
  extracting,
  completed,
  failed,
}

class BatchUploadItem {
  const BatchUploadItem({
    required this.id,
    required this.file,
    this.status = BatchItemStatus.queued,
    this.documentId,
    this.rawText,
    this.reviewedText,
    this.categoryKey,
    this.folderKey,
    this.title,
    this.documentDate,
    this.description,
    this.reflection,
    this.scholastic = const ScholasticDetails(),
    this.confidence,
    this.errorMessage,
    this.retryCount = 0,
    this.isAutoCategorized = false,
    this.isManualCategory = false,
    this.previewResult,
    this.isPreviewing = false,
    this.previewError,
  });

  final String id;
  final PickedDocument file;
  final BatchItemStatus status;
  final String? documentId;
  final String? rawText;
  final String? reviewedText;
  final String? categoryKey;
  final String? folderKey;
  final String? title;
  final DateTime? documentDate;
  final String? description;
  final String? reflection;
  final ScholasticDetails scholastic;
  bool get isTor => ScholasticDetails.isTor(categoryKey, folderKey);
  final String? confidence;
  final String? errorMessage;
  final int retryCount;
  final bool isAutoCategorized;
  final bool isManualCategory;
  final DocumentOcrResult? previewResult;
  final bool isPreviewing;
  final String? previewError;

  String get fileName => file.name;
  int get fileSize => file.sizeBytes;

  bool get isProcessing =>
      isPreviewing ||
      status == BatchItemStatus.uploading ||
      status == BatchItemStatus.uploaded ||
      status == BatchItemStatus.waitingForOcr ||
      status == BatchItemStatus.extracting;

  bool get isUploading => status == BatchItemStatus.uploading;
  bool get isWaitingForOcr => status == BatchItemStatus.waitingForOcr;
  bool get isExtracting => status == BatchItemStatus.extracting;
  bool get isUploaded => documentId != null;
  bool get isCompleted => status == BatchItemStatus.completed;
  bool get isFailed => status == BatchItemStatus.failed;
  bool get canRetry => isFailed;
  bool get isLowConfidence => confidence == 'low';

  bool get isOcrEligible =>
      file.hasSupportedUploadType &&
      (file.mimeType == 'application/pdf' ||
          file.mimeType.startsWith('image/'));

  bool get isValidForUpload =>
      categoryKey != null &&
      categoryKey!.trim().isNotEmpty &&
      folderKey != null &&
      folderKey!.trim().isNotEmpty &&
      title != null &&
      title!.trim().isNotEmpty &&
      documentDate != null &&
      (!isTor || scholastic.reflectionSatisfied(reflection));

  // Backward-compatibility getters
  bool get isReadyForReview =>
      status == BatchItemStatus.queued || status == BatchItemStatus.completed;
  bool get isSaved => isCompleted;
  bool get isValidForSave => isValidForUpload;

  BatchUploadItem copyWith({
    String? id,
    PickedDocument? file,
    BatchItemStatus? status,
    String? documentId,
    String? rawText,
    String? reviewedText,
    String? categoryKey,
    String? folderKey,
    String? title,
    DateTime? documentDate,
    String? description,
    String? reflection,
    ScholasticDetails? scholastic,
    String? confidence,
    String? errorMessage,
    int? retryCount,
    bool? isAutoCategorized,
    bool? isManualCategory,
    bool clearCategory = false,
    bool clearFolder = false,
    DocumentOcrResult? previewResult,
    bool? isPreviewing,
    String? previewError,
    bool clearPreviewError = false,
  }) {
    return BatchUploadItem(
      id: id ?? this.id,
      file: file ?? this.file,
      status: status ?? this.status,
      documentId: documentId ?? this.documentId,
      rawText: rawText ?? this.rawText,
      reviewedText: reviewedText ?? this.reviewedText,
      categoryKey: clearCategory ? null : (categoryKey ?? this.categoryKey),
      folderKey: clearFolder ? null : (folderKey ?? this.folderKey),
      title: title ?? this.title,
      documentDate: documentDate ?? this.documentDate,
      description: description ?? this.description,
      reflection: reflection ?? this.reflection,
      scholastic: scholastic ?? this.scholastic,
      confidence: confidence ?? this.confidence,
      errorMessage: errorMessage ?? this.errorMessage,
      previewResult: previewResult ?? this.previewResult,
      isPreviewing: isPreviewing ?? this.isPreviewing,
      previewError: clearPreviewError
          ? null
          : (previewError ?? this.previewError),
      retryCount: retryCount ?? this.retryCount,
      isAutoCategorized: isAutoCategorized ?? this.isAutoCategorized,
      isManualCategory: isManualCategory ?? this.isManualCategory,
    );
  }
}
