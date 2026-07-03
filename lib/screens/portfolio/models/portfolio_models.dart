// LOCATION: lib/screens/portfolio/models/portfolio_models.dart
//
// Data models for the Generate Portfolio workflow.
// Architecture is future-ready for MongoDB / OCR / PDF / DOCX integration.

/// Holds the user-entered portfolio title page information (Screen 1).
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

  /// Convert to a map for future MongoDB / API submission.
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
  }) =>
      PortfolioInfo(
        fullName: fullName ?? this.fullName,
        yearAndSection: yearAndSection ?? this.yearAndSection,
        schedule: schedule ?? this.schedule,
        instructorName: instructorName ?? this.instructorName,
        course: course ?? this.course,
        courseCode: courseCode ?? this.courseCode,
        semesterAndYear: semesterAndYear ?? this.semesterAndYear,
      );
}

/// Represents a single section row in the Portfolio Summary (Screen 2).
class PortfolioSection {
  const PortfolioSection({
    required this.name,
    required this.count,
  });

  final String name;
  final int count;

  int get totalItems => count;
}

/// Holds the full portfolio summary data (Screen 2).
/// Replace mock data with real OCR / database counts when backend is ready.
class PortfolioSummary {
  const PortfolioSummary({
    required this.sections,
  });

  final List<PortfolioSection> sections;

  int get totalItems =>
      sections.fold(0, (sum, s) => sum + s.count);

  /// MOCK DATA — replace with real data from MongoDB / OCR results.
  static PortfolioSummary get mock => const PortfolioSummary(
        sections: [
          PortfolioSection(name: 'Creative Title',     count: 5),
          PortfolioSection(name: 'Curriculum Vitae',   count: 0),
          PortfolioSection(name: 'Scholastic Record',  count: 8),
          PortfolioSection(name: 'Certificates',       count: 11),
          PortfolioSection(name: 'Accomplishments',    count: 30),
          PortfolioSection(name: 'Other Achievements', count: 2),
          PortfolioSection(name: 'College Report',     count: 8),
        ],
      );
}

/// Export format selection (Screen 3).
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