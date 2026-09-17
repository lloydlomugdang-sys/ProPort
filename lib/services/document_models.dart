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

class DocumentOcrResult {
  const DocumentOcrResult({
    required this.status,
    this.rawText,
    this.reviewedText,
    this.engine,
    this.processedAt,
    this.updatedAt,
    this.metadataSuggestions,
    this.metadataAnalysis,
  });

  final DocumentOcrStatus status;
  final String? rawText;
  final String? reviewedText;
  final String? engine;
  final DateTime? processedAt;
  final DateTime? updatedAt;
  final DocumentMetadataSuggestions? metadataSuggestions;
  final DocumentMetadataAnalysis? metadataAnalysis;

  bool get isReady => status == DocumentOcrStatus.ready;

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
  const PickedDocument({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;

  int get sizeBytes => bytes.length;

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
