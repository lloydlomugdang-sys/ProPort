import 'dart:io';
import 'dart:typed_data';

enum DocumentOcrStatus { notProcessed, processing, ready, failed }

class DocumentMetadataAnalysis {
  const DocumentMetadataAnalysis({
    required this.source,
    required this.aiStatus,
  });

  final String source;
  final String aiStatus;

  factory DocumentMetadataAnalysis.fromJson(Map<String, dynamic> json) {
    final source = _requiredString(json, 'source');
    final status = _requiredString(json, 'aiStatus');
    if (!const ['gemini', 'rules', 'none'].contains(source) ||
        !const [
          'success',
          'unavailable',
          'disabled',
          'not_needed',
        ].contains(status)) {
      throw const FormatException();
    }
    return DocumentMetadataAnalysis(source: source, aiStatus: status);
  }
}

class DocumentMetadataSuggestions {
  const DocumentMetadataSuggestions({
    this.categoryKey,
    this.folderKey,
    this.title,
    this.documentDate,
    this.description,
    this.confidence,
  });

  final String? categoryKey;
  final String? folderKey;
  final String? title;
  final DateTime? documentDate;
  final String? description;
  final String? confidence;

  bool get isEmpty =>
      categoryKey == null &&
      folderKey == null &&
      title == null &&
      documentDate == null &&
      description == null;

  bool get isLowConfidence => confidence == 'low';

  factory DocumentMetadataSuggestions.fromJson(Map<String, dynamic> json) {
    final date = _optionalString(json, 'documentDate');
    final parsed = date == null ? null : DateTime.tryParse(date);
    if (date != null &&
        (parsed == null ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
            parsed.toIso8601String().substring(0, 10) != date)) {
      throw const FormatException();
    }
    final conf = _optionalString(json, 'confidence');
    if (conf != null && !const ['high', 'medium', 'low'].contains(conf)) {
      throw const FormatException();
    }
    return DocumentMetadataSuggestions(
      categoryKey: _optionalString(json, 'categoryKey'),
      folderKey: _optionalString(json, 'folderKey'),
      title: _optionalString(json, 'title'),
      documentDate: parsed,
      description: _optionalString(json, 'description'),
      confidence: conf,
    );
  }
}

class DocumentOcrPage {
  const DocumentOcrPage({
    required this.pageNumber,
    required this.status,
    this.originalFileName,
    this.mimeType,
    this.rawText,
  });

  final int pageNumber;
  final String status;
  final String? originalFileName;
  final String? mimeType;
  final String? rawText;

  bool get isFailed => status == 'failed';

  factory DocumentOcrPage.fromJson(Map<String, dynamic> json) {
    final pageNumber = json['pageNumber'];
    if (pageNumber is! int || pageNumber < 1) throw const FormatException();
    final status = _requiredString(json, 'status');
    if (status != 'ready' && status != 'failed') throw const FormatException();
    return DocumentOcrPage(
      pageNumber: pageNumber,
      status: status,
      originalFileName: _optionalString(json, 'originalFileName'),
      mimeType: _optionalString(json, 'mimeType'),
      rawText: _optionalString(json, 'rawText'),
    );
  }
}

class DocumentOcrResult {
  const DocumentOcrResult({
    required this.status,
    this.rawText,
    this.reviewedText,
    this.engine,
    this.processedAt,
    this.updatedAt,
    this.pages = const [],
    this.metadataSuggestions,
    this.metadataAnalysis,
  });

  final DocumentOcrStatus status;
  final String? rawText;
  final String? reviewedText;
  final String? engine;
  final DateTime? processedAt;
  final DateTime? updatedAt;
  final List<DocumentOcrPage> pages;
  final DocumentMetadataSuggestions? metadataSuggestions;
  final DocumentMetadataAnalysis? metadataAnalysis;

  bool get isReady => status == DocumentOcrStatus.ready;

  bool get hasFailedPages => pages.any((page) => page.isFailed);

  List<int> get failedPageNumbers => pages
      .where((page) => page.isFailed)
      .map((page) => page.pageNumber)
      .toList(growable: false);

  factory DocumentOcrResult.fromJson(Map<String, dynamic> json) {
    final status = switch (_requiredString(json, 'status')) {
      'not_processed' => DocumentOcrStatus.notProcessed,
      'processing' => DocumentOcrStatus.processing,
      'ready' => DocumentOcrStatus.ready,
      'failed' => DocumentOcrStatus.failed,
      _ => throw const FormatException(),
    };
    final processedAt = _optionalDateTime(json, 'processedAt');
    final updatedAt = _optionalDateTime(json, 'updatedAt');
    final rawPages = json['pages'];
    if (rawPages != null && rawPages is! List) {
      throw const FormatException();
    }
    final pages = rawPages is List
        ? rawPages
              .whereType<Map<String, dynamic>>()
              .map(DocumentOcrPage.fromJson)
              .toList(growable: false)
        : const <DocumentOcrPage>[];
    final suggestions = json['metadataSuggestions'];
    final analysis = json['metadataAnalysis'];
    if (analysis != null && analysis is! Map<String, dynamic>) {
      throw const FormatException();
    }
    if (suggestions != null && suggestions is! Map<String, dynamic>) {
      throw const FormatException();
    }
    return DocumentOcrResult(
      status: status,
      rawText: _optionalString(json, 'rawText'),
      reviewedText: _optionalString(json, 'reviewedText'),
      engine: _optionalString(json, 'engine'),
      processedAt: processedAt,
      updatedAt: updatedAt,
      pages: pages,
      metadataAnalysis: analysis == null
          ? null
          : DocumentMetadataAnalysis.fromJson(analysis as Map<String, dynamic>),
      metadataSuggestions: suggestions == null
          ? null
          : DocumentMetadataSuggestions.fromJson(
              suggestions as Map<String, dynamic>,
            ),
    );
  }
}

class PickedDocument {
  PickedDocument({
    required this.name,
    required this.mimeType,
    Uint8List? bytes,
    this.path,
    int? sizeBytes,
  }) : _bytes = bytes,
       _sizeBytes = sizeBytes ?? bytes?.length ?? 0 {
    if (bytes == null && (path == null || path!.isEmpty)) {
      throw ArgumentError('Either bytes or path must be provided.');
    }
  }

  final String name;
  final String mimeType;
  final String? path;
  Uint8List? _bytes;
  final int _sizeBytes;

  int get sizeBytes => _sizeBytes;

  bool get hasBytes => _bytes != null;

  Uint8List get bytes {
    final current = _bytes;
    if (current != null) return current;
    throw StateError(
      'Document bytes have not been materialized. Call readBytes() asynchronously.',
    );
  }

  Future<Uint8List> readBytes() async {
    final current = _bytes;
    if (current != null) return current;
    final filePath = path;
    if (filePath == null || filePath.isEmpty) {
      throw const FileSystemException(
        'File path is unavailable and bytes are not loaded.',
      );
    }
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File no longer exists at path: $filePath');
    }
    final data = await file.readAsBytes();
    _bytes = data;
    return data;
  }

  void releaseBytes() {
    if (path != null && path!.isNotEmpty) {
      _bytes = null;
    }
  }

  bool get hasSupportedUploadType {
    final extension = name.split('.').last.toLowerCase();
    return switch (mimeType.toLowerCase()) {
      'application/pdf' => extension == 'pdf',
      'image/jpeg' => extension == 'jpg' || extension == 'jpeg',
      'image/png' => extension == 'png',
      _ => false,
    };
  }
}

class DocumentFolder {
  const DocumentFolder({required this.key, required this.name});

  final String key;
  final String name;

  factory DocumentFolder.fromJson(Map<String, dynamic> json) {
    return DocumentFolder(
      key: _requiredString(json, 'key'),
      name: _requiredString(json, 'name'),
    );
  }
}

class DocumentCategory {
  const DocumentCategory({
    required this.key,
    required this.name,
    required this.folders,
  });

  final String key;
  final String name;
  final List<DocumentFolder> folders;

  factory DocumentCategory.fromJson(Map<String, dynamic> json) {
    final values = json['folders'];
    if (values is! List) throw const FormatException();
    return DocumentCategory(
      key: _requiredString(json, 'key'),
      name: _requiredString(json, 'name'),
      folders: values
          .map((value) {
            if (value is! Map<String, dynamic>) throw const FormatException();
            return DocumentFolder.fromJson(value);
          })
          .toList(growable: false),
    );
  }
}

class DocumentAttachmentRecord {
  const DocumentAttachmentRecord({
    required this.id,
    required this.originalFileName,
    required this.mimeType,
    required this.fileKind,
    required this.extension,
    required this.sizeBytes,
    required this.order,
  });

  final String id;
  final String originalFileName;
  final String mimeType;
  final String fileKind;
  final String extension;
  final int sizeBytes;
  final int order;

  factory DocumentAttachmentRecord.fromJson(Map<String, dynamic> json) {
    return DocumentAttachmentRecord(
      id: _requiredString(json, 'id'),
      originalFileName: _requiredString(json, 'originalFileName'),
      mimeType: _requiredString(json, 'mimeType'),
      fileKind: _requiredString(json, 'fileKind'),
      extension: _requiredString(json, 'extension'),
      sizeBytes: json['sizeBytes'] as int,
      order: json['order'] as int,
    );
  }
}

class DocumentRecord {
  const DocumentRecord({
    required this.id,
    required this.categoryKey,
    required this.folderKey,
    required this.title,
    required this.documentDate,
    required this.originalFileName,
    required this.mimeType,
    required this.fileKind,
    required this.extension,
    required this.sizeBytes,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.reflection,
    this.attachments,
  });

  final String id;
  final String categoryKey;
  final String folderKey;
  final String title;
  final DateTime documentDate;
  final String? description;
  final String? reflection;
  final String originalFileName;
  final String mimeType;
  final String fileKind;
  final String extension;
  final int sizeBytes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<DocumentAttachmentRecord>? attachments;

  String get fileTypeLabel => fileKind == 'pdf' ? 'PDF' : 'Image';

  List<DocumentAttachmentRecord> get effectiveAttachments {
    if (attachments != null && attachments!.isNotEmpty) {
      return attachments!;
    }
    return [
      DocumentAttachmentRecord(
        id: '1',
        originalFileName: originalFileName,
        mimeType: mimeType,
        fileKind: fileKind,
        extension: extension,
        sizeBytes: sizeBytes,
        order: 0,
      ),
    ];
  }

  int get pageCount => effectiveAttachments.length;

  factory DocumentRecord.fromJson(Map<String, dynamic> json) {
    final documentDate = DateTime.tryParse(
      _requiredString(json, 'documentDate'),
    );
    final createdAt = DateTime.tryParse(_requiredString(json, 'createdAt'));
    final updatedAt = DateTime.tryParse(_requiredString(json, 'updatedAt'));
    final sizeBytes = json['sizeBytes'];
    if (documentDate == null ||
        createdAt == null ||
        updatedAt == null ||
        sizeBytes is! int) {
      throw const FormatException();
    }
    final rawAttachments = json['attachments'];
    final List<DocumentAttachmentRecord>? attachments = rawAttachments is List
        ? rawAttachments
              .whereType<Map<String, dynamic>>()
              .map(DocumentAttachmentRecord.fromJson)
              .toList(growable: false)
        : null;
    return DocumentRecord(
      id: _requiredString(json, 'id'),
      categoryKey: _requiredString(json, 'categoryKey'),
      folderKey: _requiredString(json, 'folderKey'),
      title: _requiredString(json, 'title'),
      documentDate: documentDate,
      description: _optionalString(json, 'description'),
      reflection: _optionalString(json, 'reflection'),
      originalFileName: _requiredString(json, 'originalFileName'),
      mimeType: _requiredString(json, 'mimeType'),
      fileKind: _requiredString(json, 'fileKind'),
      extension: _requiredString(json, 'extension'),
      sizeBytes: sizeBytes,
      createdAt: createdAt,
      updatedAt: updatedAt,
      attachments: attachments,
    );
  }
}

class DocumentSummary {
  const DocumentSummary({
    required this.totalCount,
    required this.categoryCounts,
    required this.folderCounts,
  });

  static const empty = DocumentSummary(
    totalCount: 0,
    categoryCounts: {},
    folderCounts: {},
  );

  final int totalCount;
  final Map<String, int> categoryCounts;
  final Map<String, int> folderCounts;

  int categoryCount(String categoryKey) => categoryCounts[categoryKey] ?? 0;

  int folderCount(String categoryKey, String folderKey) =>
      folderCounts['$categoryKey/$folderKey'] ?? 0;

  int get creativeTitleCount => folderCounts.entries
      .where((entry) => entry.key.endsWith('/creative-title'))
      .fold(0, (total, entry) => total + entry.value);

  factory DocumentSummary.fromJson(Map<String, dynamic> json) {
    final totalCount = json['totalCount'];
    if (totalCount is! int) throw const FormatException();
    return DocumentSummary(
      totalCount: totalCount,
      categoryCounts: _countMap(json['categoryCounts']),
      folderCounts: _countMap(json['folderCounts']),
    );
  }

  DocumentSummary adding(DocumentRecord document) {
    final categories = Map<String, int>.from(categoryCounts);
    final folders = Map<String, int>.from(folderCounts);
    categories[document.categoryKey] = categoryCount(document.categoryKey) + 1;
    final folderKey = '${document.categoryKey}/${document.folderKey}';
    folders[folderKey] = (folders[folderKey] ?? 0) + 1;
    return DocumentSummary(
      totalCount: totalCount + 1,
      categoryCounts: categories,
      folderCounts: folders,
    );
  }

  DocumentSummary removing(DocumentRecord document) {
    final categories = Map<String, int>.from(categoryCounts);
    final folders = Map<String, int>.from(folderCounts);
    _decrement(categories, document.categoryKey);
    _decrement(folders, '${document.categoryKey}/${document.folderKey}');
    return DocumentSummary(
      totalCount: totalCount > 0 ? totalCount - 1 : 0,
      categoryCounts: categories,
      folderCounts: folders,
    );
  }

  static void _decrement(Map<String, int> values, String key) {
    final next = (values[key] ?? 0) - 1;
    if (next > 0) {
      values[key] = next;
    } else {
      values.remove(key);
    }
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) throw const FormatException();
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw const FormatException();
  return value;
}

DateTime? _optionalDateTime(Map<String, dynamic> json, String key) {
  final value = _optionalString(json, key);
  if (value == null) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw const FormatException();
  return parsed;
}

Map<String, int> _countMap(Object? value) {
  if (value is! Map<String, dynamic>) throw const FormatException();
  final result = <String, int>{};
  for (final entry in value.entries) {
    if (entry.value is! int) throw const FormatException();
    result[entry.key] = entry.value as int;
  }
  return Map.unmodifiable(result);
}

class CompiledDocumentProposal {
  const CompiledDocumentProposal({
    required this.startPage,
    required this.endPage,
    required this.categoryKey,
    required this.folderKey,
    required this.title,
    this.documentDate,
    this.confidence = 0.8,
    this.rationale,
    this.warning,
  });

  final int startPage;
  final int endPage;
  final String categoryKey;
  final String folderKey;
  final String title;
  final DateTime? documentDate;
  final double confidence;
  final String? rationale;
  final String? warning;

  factory CompiledDocumentProposal.fromJson(Map<String, dynamic> json) {
    final start = json['startPage'];
    final end = json['endPage'];
    if (start is! int || end is! int) throw const FormatException();
    final dateStr = _optionalString(json, 'documentDate');
    DateTime? parsedDate;
    if (dateStr != null && dateStr.isNotEmpty) {
      parsedDate = DateTime.tryParse(dateStr);
    }
    final confRaw = json['confidence'];
    final conf = confRaw is num ? confRaw.toDouble() : 0.8;
    // An unresolved proposal deliberately has no taxonomy selection yet.
    final category = json['categoryKey'];
    final folder = json['folderKey'];
    if (category is! String || folder is! String) {
      throw const FormatException();
    }

    return CompiledDocumentProposal(
      startPage: start,
      endPage: end,
      categoryKey: category,
      folderKey: folder,
      title: _requiredString(json, 'title'),
      documentDate: parsedDate,
      confidence: conf,
      rationale: _optionalString(json, 'rationale'),
      warning: _optionalString(json, 'warning'),
    );
  }

  CompiledDocumentProposal copyWith({
    int? startPage,
    int? endPage,
    String? categoryKey,
    String? folderKey,
    String? title,
    DateTime? documentDate,
    double? confidence,
    String? rationale,
    String? warning,
  }) {
    return CompiledDocumentProposal(
      startPage: startPage ?? this.startPage,
      endPage: endPage ?? this.endPage,
      categoryKey: categoryKey ?? this.categoryKey,
      folderKey: folderKey ?? this.folderKey,
      title: title ?? this.title,
      documentDate: documentDate ?? this.documentDate,
      confidence: confidence ?? this.confidence,
      rationale: rationale ?? this.rationale,
      warning: warning ?? this.warning,
    );
  }
}

class CompiledPageResult {
  const CompiledPageResult({
    required this.pageNumber,
    required this.text,
    required this.source,
    required this.status,
  });
  final int pageNumber;
  final String text;
  final String source;
  final String status;
  bool get isUnresolved => status == 'unresolved' || source == 'failed';
  factory CompiledPageResult.fromJson(Map<String, dynamic> json) =>
      CompiledPageResult(
        pageNumber: json['pageNumber'] as int,
        text: json['text'] as String,
        source: json['source'] as String,
        status: json['status'] as String,
      );
}

class CompiledAnalysisResult {
  const CompiledAnalysisResult({
    required this.sessionId,
    required this.originalFileName,
    required this.totalPages,
    required this.documents,
    this.pages = const [],
    this.detection = 'needs_review',
    this.metadataSuggestions,
    this.metadataAnalysis,
  });

  final String sessionId;
  final String originalFileName;
  final int totalPages;
  final List<CompiledDocumentProposal> documents;
  final List<CompiledPageResult> pages;
  final String detection;
  final DocumentMetadataSuggestions? metadataSuggestions;
  final DocumentMetadataAnalysis? metadataAnalysis;
  bool get hasUnresolvedPages => pages.any((page) => page.isUnresolved);

  factory CompiledAnalysisResult.fromJson(Map<String, dynamic> json) {
    final total = json['totalPages'];
    if (total is! int) throw const FormatException();
    final docsRaw = json['documents'];
    if (docsRaw is! List) throw const FormatException();

    return CompiledAnalysisResult(
      sessionId: _requiredString(json, 'sessionId'),
      originalFileName: _requiredString(json, 'originalFileName'),
      totalPages: total,
      detection: json['detection'] as String? ?? 'needs_review',
      metadataSuggestions: json['metadataSuggestions'] == null
          ? null
          : DocumentMetadataSuggestions.fromJson(
              json['metadataSuggestions'] as Map<String, dynamic>,
            ),
      metadataAnalysis: json['metadataAnalysis'] == null
          ? null
          : DocumentMetadataAnalysis.fromJson(
              json['metadataAnalysis'] as Map<String, dynamic>,
            ),
      pages: (json['pages'] as List? ?? const [])
          .map(
            (page) => CompiledPageResult.fromJson(page as Map<String, dynamic>),
          )
          .toList(),
      documents: docsRaw
          .whereType<Map<String, dynamic>>()
          .map(CompiledDocumentProposal.fromJson)
          .toList(),
    );
  }
}

class CompiledSplitSegment {
  const CompiledSplitSegment({
    required this.startPage,
    required this.endPage,
    required this.categoryKey,
    required this.folderKey,
    required this.title,
    this.documentDate,
    this.description,
    this.reflection,
  });

  final int startPage;
  final int endPage;
  final String categoryKey;
  final String folderKey;
  final String title;
  final DateTime? documentDate;
  final String? description;
  final String? reflection;

  Map<String, dynamic> toJson() {
    final date = documentDate ?? DateTime.now();
    final dateStr =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return {
      'startPage': startPage,
      'endPage': endPage,
      'categoryKey': categoryKey,
      'folderKey': folderKey,
      'title': title.trim(),
      'documentDate': dateStr,
      if (description != null && description!.trim().isNotEmpty)
        'description': description!.trim(),
      if (reflection != null && reflection!.trim().isNotEmpty)
        'reflection': reflection!.trim(),
    };
  }
}
