import 'portfolio_schedule.dart';
import '../../../services/document_models.dart';

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
  });

  final String fullName;
  final String yearAndSection;
  final String schedule;
  final String instructorName;
  final String course;
  final String courseCode;
  final String semesterAndYear;

  String get formattedSchedule => PortfolioSchedule.displayValue(schedule);

  factory PortfolioInfo.fromJson(Map<String, dynamic> json) {
    String stringValue(String key) {
      final value = json[key];
      if (value is! String) throw const FormatException();
      return value;
    }

    return PortfolioInfo(
      fullName: stringValue('fullName'),
      yearAndSection: stringValue('yearAndSection'),
      schedule: stringValue('schedule'),
      instructorName: stringValue('instructorName'),
      course: stringValue('course'),
      courseCode: stringValue('courseCode'),
      semesterAndYear: stringValue('semesterAndYear'),
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
  };

  PortfolioInfo copyWith({
    String? fullName,
    String? yearAndSection,
    String? schedule,
    String? instructorName,
    String? course,
    String? courseCode,
    String? semesterAndYear,
  }) => PortfolioInfo(
    fullName: fullName ?? this.fullName,
    yearAndSection: yearAndSection ?? this.yearAndSection,
    schedule: schedule ?? this.schedule,
    instructorName: instructorName ?? this.instructorName,
    course: course ?? this.course,
    courseCode: courseCode ?? this.courseCode,
    semesterAndYear: semesterAndYear ?? this.semesterAndYear,
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

  static const categorySections = {
    'curriculum-vitae': 'Curriculum Vitae',
    'scholastic-record': 'Scholastic Record',
    'certificates': 'Certificates',
    'accomplishments': 'Accomplishments',
    'other-achievements': 'Other Achievements',
    'college-report': 'College Report',
  };

  /// Use server-wide counts, not the document list (which can be limited).
  /// Creative titles have their own section and are counted only once.
  factory PortfolioSummary.fromDocumentSummary(DocumentSummary documents) {
    return PortfolioSummary(
      totalItems: documents.totalCount,
      sections: [
        PortfolioSection(
          name: 'Creative Title',
          count: documents.creativeTitleCount,
        ),
        for (final entry in categorySections.entries)
          PortfolioSection(
            name: entry.value,
            count:
                (documents.categoryCount(entry.key) -
                        documents.folderCount(entry.key, 'creative-title'))
                    .clamp(0, documents.totalCount),
          ),
      ],
    );
  }

  static String sectionFor(DocumentRecord document) =>
      document.folderKey == 'creative-title'
      ? 'Creative Title'
      : categorySections[document.categoryKey] ?? document.categoryKey;

  /// Only for a known-empty collection, never as a loading/error placeholder.
  static PortfolioSummary get empty => const PortfolioSummary(
    sections: [
      PortfolioSection(name: 'Creative Title', count: 0),
      PortfolioSection(name: 'Curriculum Vitae', count: 0),
      PortfolioSection(name: 'Scholastic Record', count: 0),
      PortfolioSection(name: 'Certificates', count: 0),
      PortfolioSection(name: 'Accomplishments', count: 0),
      PortfolioSection(name: 'Other Achievements', count: 0),
      PortfolioSection(name: 'College Report', count: 0),
    ],
  );
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
        return 'Best for printing and sharing.';
      case ExportFormat.docx:
        return 'Best for editing.';
    }
  }
}
