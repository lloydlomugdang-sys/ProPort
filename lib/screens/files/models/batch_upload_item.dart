import 'package:proport_app/services/document_models.dart';

enum BatchItemStatus {
  waiting,
  extractingText,
  aiCategorizing,
  readyForReview,
  uploading,
  saved,
  failed,
}

class BatchUploadItem {
  const BatchUploadItem({
    required this.id,
    required this.file,
    this.status = BatchItemStatus.waiting,
    this.rawText,
    this.reviewedText,
    this.categoryKey,
    this.folderKey,
    this.title,
    this.documentDate,
    this.description,
    this.reflection,
    this.confidence,
    this.errorMessage,
    this.retryCount = 0,
  });

  final String id;
  final PickedDocument file;
  final BatchItemStatus status;
  final String? rawText;
  final String? reviewedText;
  final String? categoryKey;
  final String? folderKey;
  final String? title;
  final DateTime? documentDate;
  final String? description;
  final String? reflection;
  final String? confidence;
  final String? errorMessage;
  final int retryCount;

  String get fileName => file.name;
  int get fileSize => file.sizeBytes;

  bool get isProcessing =>
      status == BatchItemStatus.waiting ||
      status == BatchItemStatus.extractingText ||
      status == BatchItemStatus.aiCategorizing ||
      status == BatchItemStatus.uploading;

  bool get isReadyForReview => status == BatchItemStatus.readyForReview;
  bool get isSaved => status == BatchItemStatus.saved;
  bool get isFailed => status == BatchItemStatus.failed;
  bool get isLowConfidence => confidence == 'low';

  bool get isValidForSave =>
      categoryKey != null &&
      categoryKey!.trim().isNotEmpty &&
      folderKey != null &&
      folderKey!.trim().isNotEmpty &&
      title != null &&
      title!.trim().isNotEmpty &&
      documentDate != null;

  BatchUploadItem copyWith({
    String? id,
    PickedDocument? file,
    BatchItemStatus? status,
    String? rawText,
    String? reviewedText,
    String? categoryKey,
    String? folderKey,
    String? title,
    DateTime? documentDate,
    String? description,
    String? reflection,
    String? confidence,
    String? errorMessage,
    int? retryCount,
    bool clearCategory = false,
    bool clearFolder = false,
  }) {
    return BatchUploadItem(
      id: id ?? this.id,
      file: file ?? this.file,
      status: status ?? this.status,
      rawText: rawText ?? this.rawText,
      reviewedText: reviewedText ?? this.reviewedText,
      categoryKey: clearCategory ? null : (categoryKey ?? this.categoryKey),
      folderKey: clearFolder ? null : (folderKey ?? this.folderKey),
      title: title ?? this.title,
      documentDate: documentDate ?? this.documentDate,
      description: description ?? this.description,
      reflection: reflection ?? this.reflection,
      confidence: confidence ?? this.confidence,
      errorMessage: errorMessage ?? this.errorMessage,
      retryCount: retryCount ?? this.retryCount,
    );
  }
}

