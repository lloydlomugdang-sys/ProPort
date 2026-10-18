class ScholasticDetails {
  const ScholasticDetails({
    this.studyYear,
    this.semester,
    this.reflectionIncluded = false,
  });
  final int? studyYear;
  final String? semester;
  final bool reflectionIncluded;
  static const semesters = ['1st Semester', '2nd Semester'];
  String? get period => studyYear == null || semester == null
      ? null
      : 'Year $studyYear / $semester';
  Map<String, dynamic> toJson() => {
    if (studyYear != null) 'studyYear': studyYear,
    if (semester != null) 'semester': semester,
    'reflectionIncluded': reflectionIncluded,
  };
  factory ScholasticDetails.fromJson(Map<String, dynamic> json) =>
      ScholasticDetails(
        studyYear: json['studyYear'] as int?,
        semester: json['semester'] as String?,
        reflectionIncluded: json['reflectionIncluded'] == true,
      );
  static bool isTor(String? category, String? folder) =>
      category == 'scholastic-record' &&
      folder == 'unofficial-tor-with-reflections';
  bool reflectionSatisfied(String? reflection) =>
      reflectionIncluded || (reflection?.trim().isNotEmpty ?? false);
}

class ScholasticCoverage {
  const ScholasticCoverage({
    this.missingReflection = 0,
    this.missingPeriod = 0,
    this.periodCounts = const {},
  });
  final int missingReflection;
  final int missingPeriod;
  final Map<String, int> periodCounts;
  factory ScholasticCoverage.fromJson(Map<String, dynamic> json) =>
      ScholasticCoverage(
        missingReflection: json['missingReflection'] as int,
        missingPeriod: json['missingPeriod'] as int,
        periodCounts: Map<String, int>.from(json['periodCounts'] as Map),
      );

  /// A recorded period is evidence, never proof of a complete degree. No
  /// authoritative required-period set has been supplied by the institution.
  bool get isComplete => false;
  List<String> get reasons => [
    if (missingReflection > 0) 'Missing: TOR reflection ($missingReflection)',
    if (missingPeriod > 0) 'Missing: TOR year / semester ($missingPeriod)',
    '${periodCounts.length} recorded periods; required semester coverage awaits confirmation.',
  ];
  ScholasticCoverage adjust(
    ScholasticDetails? details,
    String? reflection,
    int delta,
  ) {
    final value = details ?? const ScholasticDetails();
    final periods = Map<String, int>.from(periodCounts);
    if (value.period != null) {
      final count = (periods[value.period] ?? 0) + delta;
      if (count <= 0) {
        periods.remove(value.period);
      } else {
        periods[value.period!] = count;
      }
    }
    return ScholasticCoverage(
      missingReflection:
          (missingReflection +
                  (value.reflectionSatisfied(reflection) ? 0 : delta))
              .clamp(0, 1000000),
      missingPeriod: (missingPeriod + (value.period == null ? delta : 0)).clamp(
        0,
        1000000,
      ),
      periodCounts: periods,
    );
  }
}
