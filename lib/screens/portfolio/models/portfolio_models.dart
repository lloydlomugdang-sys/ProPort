import 'portfolio_schedule.dart';
import '../../../services/document_models.dart';
import '../../../services/portfolio_template.dart';

/// Holds the user-entered portfolio title-page information.
class PortfolioInfo {
  const PortfolioInfo({
    required this.fullName,
    required this.yearAndSection,
    required this.schedule,
    required this.instructorName,
    this.course = '',
    this.courseCode = '',
    this.semesterAndYear = '',
    this.creativeTitles = const {},
    this.templateOverrides,
  });

  final String fullName;
  final String yearAndSection;
  final String schedule;
  final String instructorName;
  final String course;
  final String courseCode;
  final String semesterAndYear;
  final Map<String, String> creativeTitles;
  final PortfolioTemplateOverride? templateOverrides;

  static const fieldLabels = {
    'fullName': 'Full Name',
    'yearAndSection': 'Year & Section',
    'schedule': 'Schedule',
    'instructorName': "Instructor's Name",
    'course': 'Course',
    'courseCode': 'Course Code',
    'semesterAndYear': 'Semester & Academic Year',
  };
  static const fieldLimits = {
    'fullName': 200,
    'yearAndSection': 100,
    'schedule': 200,
    'instructorName': 200,
    'course': 200,
    'courseCode': 100,
    'semesterAndYear': 100,
  };

  Map<String, String> get validationErrors => {
    for (final entry in toMap().entries.where(
      (e) => fieldLabels.containsKey(e.key),
    ))
      if ((entry.value as String).trim().isEmpty)
        entry.key: '${fieldLabels[entry.key]} is required.'
      else if ((entry.value as String).trim().length > fieldLimits[entry.key]!)
        entry.key:
            '${fieldLabels[entry.key]} must be ${fieldLimits[entry.key]} characters or fewer.',
  };

  Map<String, dynamic> get normalizedMap => {
    for (final entry in toMap().entries.where(
      (e) => fieldLabels.containsKey(e.key),
    ))
      entry.key: (entry.value as String).trim(),
    if (creativeTitles.isNotEmpty)
      'creativeTitles': {
        for (final e in creativeTitles.entries) e.key: e.value.trim(),
      },
    if (templateOverrides != null) 'templateOverrides': templateOverrides!.toJson(),
  };

  String get formattedSchedule => PortfolioSchedule.displayValue(schedule);

  factory PortfolioInfo.fromJson(Map<String, dynamic> json) {
    String stringValue(String key) {
      final value = json[key];
      if (value is! String) throw const FormatException();
      return value;
    }

    final rawOverrides = json['templateOverrides'];
    PortfolioTemplateOverride? templateOverrides;
    if (rawOverrides is Map<String, dynamic>) {
      templateOverrides = PortfolioTemplateOverride.fromJson(rawOverrides);
    } else if (rawOverrides is Map) {
      templateOverrides = PortfolioTemplateOverride.fromJson(
        Map<String, dynamic>.from(rawOverrides),
      );
    }

    return PortfolioInfo(
      fullName: stringValue('fullName'),
      yearAndSection: stringValue('yearAndSection'),
      schedule: stringValue('schedule'),
      instructorName: stringValue('instructorName'),
      course: stringValue('course'),
      courseCode: stringValue('courseCode'),
      semesterAndYear: stringValue('semesterAndYear'),
      creativeTitles: Map<String, String>.from(
        json['creativeTitles'] as Map? ?? const {},
      ),
      templateOverrides: templateOverrides,
    );
  }

  Map<String, dynamic> toMap() => {
    'fullName': fullName,
    'yearAndSection': yearAndSection,
    'schedule': schedule,
    'instructorName': instructorName,
    'course': course,
    'courseCode': courseCode,
    'semesterAndYear': semesterAndYear,
    if (creativeTitles.isNotEmpty) 'creativeTitles': creativeTitles,
    if (templateOverrides != null) 'templateOverrides': templateOverrides!.toJson(),
  };

  PortfolioInfo copyWith({
    String? fullName,
    String? yearAndSection,
    String? schedule,
    String? instructorName,
    String? course,
    String? courseCode,
    String? semesterAndYear,
    Map<String, String>? creativeTitles,
    PortfolioTemplateOverride? templateOverrides,
    bool clearTemplateOverrides = false,
  }) => PortfolioInfo(
    fullName: fullName ?? this.fullName,
    yearAndSection: yearAndSection ?? this.yearAndSection,
    schedule: schedule ?? this.schedule,
    instructorName: instructorName ?? this.instructorName,
    course: course ?? this.course,
    courseCode: courseCode ?? this.courseCode,
    semesterAndYear: semesterAndYear ?? this.semesterAndYear,
    creativeTitles: creativeTitles ?? this.creativeTitles,
    templateOverrides: clearTemplateOverrides
        ? null
        : (templateOverrides ?? this.templateOverrides),
  );
}

/// A persisted, authenticated-user-owned portfolio title page.
class PortfolioRecord {
  const PortfolioRecord({
    required this.id,
    required this.info,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final PortfolioInfo info;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory PortfolioRecord.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    if (id is! String || id.isEmpty || createdAt == null || updatedAt == null) {
      throw const FormatException();
    }
    return PortfolioRecord(
      id: id,
      info: PortfolioInfo.fromJson(json),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class PortfolioSection {
  const PortfolioSection({required this.name, required this.count});

  final String name;
  final int count;

  int get totalItems => count;
}

class PortfolioSummary {
  const PortfolioSummary({required this.sections, int? totalItems})
    : _totalItems = totalItems;

  final List<PortfolioSection> sections;
  final int? _totalItems;

  int get totalItems =>
      _totalItems ?? sections.fold(0, (sum, section) => sum + section.count);

  /// Use server-wide counts, not the document list (which can be limited).
  /// Creative Title is a counter, not a separate generated section.
  factory PortfolioSummary.fromDocumentSummary(
    DocumentSummary documents,
    PortfolioTemplate template,
  ) {
    final enabled = template.enabledSections.toList();
    final creativeCount = enabled
        .where((s) => s.generateCreativeTitle)
        .fold<int>(
          0,
          (sum, s) => sum + documents.folderCount(s.key, 'creative-title'),
        );
    return PortfolioSummary(
      sections: [
        PortfolioSection(name: 'Creative Title', count: creativeCount),
        for (final section in enabled)
          PortfolioSection(
            name: section.label,
            count:
                (documents.categoryCount(section.key) -
                        documents.folderCount(section.key, 'creative-title'))
                    .clamp(0, documents.totalCount),
          ),
      ],
    );
  }
}

enum ExportFormat { pdf, docx }

extension ExportFormatExtension on ExportFormat {
  String get label {
    switch (this) {
      case ExportFormat.pdf:
        return 'PDF Document';
      case ExportFormat.docx:
        return 'DOCX Document';
    }
  }

  String get subtitle {
    switch (this) {
      case ExportFormat.pdf:
        return 'Includes saved image and PDF evidence.';
      case ExportFormat.docx:
        return 'Editable text with embedded evidence images.';
    }
  }
}
