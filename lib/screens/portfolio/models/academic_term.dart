/// UI values only; these do not define the number of required TOR periods.
class AcademicTerm {
  static const semesters = ['1st Semester', '2nd Semester'];
  static String? validateYear(String input) {
    final match = RegExp(r'^(\d{4})-(\d{4})$').firstMatch(input.trim());
    if (match == null || int.parse(match[2]!) != int.parse(match[1]!) + 1) {
      return 'Enter consecutive years, for example 2025-2026.';
    }
    return null;
  }

  static (String?, String) parse(String value) {
    final semester = RegExp(
      r'\b(1st|2nd|First|Second)\s+Sem(?:ester)?\b',
      caseSensitive: false,
    ).firstMatch(value);
    final year = RegExp(r'\b\d{4}-\d{4}\b').firstMatch(value);
    return (
      semester == null
          ? null
          : ['1st', 'first'].contains(semester[1]!.toLowerCase())
          ? semesters[0]
          : semesters[1],
      year?[0] ?? '',
    );
  }
}
