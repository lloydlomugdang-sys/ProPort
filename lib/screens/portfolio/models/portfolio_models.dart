import 'portfolio_schedule.dart';

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
  const PortfolioSummary({required this.sections});

  final List<PortfolioSection> sections;

  int get totalItems => sections.fold(0, (sum, section) => sum + section.count);

  /// Metadata CRUD cannot determine document counts, so the supported
  /// sections remain visible with honest zero values until document CRUD.
  static PortfolioSummary get empty => const PortfolioSummary(
    sections: [
      PortfolioSection(name: 'Creative Titles', count: 0),
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
