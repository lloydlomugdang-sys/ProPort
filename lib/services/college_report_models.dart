class CollegeReportOption {
  CollegeReportOption.fromJson(Map<String, dynamic> json)
    : value = json['value'] as Object,
      label = json['label'] as String;
  final Object value;
  final String label;
}

class CollegeReportQuestion {
  CollegeReportQuestion.fromJson(Map<String, dynamic> json)
    : key = json['key'] as String,
      label = json['label'] as String,
      text = json['text'] as String;
  final String key;
  final String label;
  final String text;
}

class CollegeReportSection {
  CollegeReportSection.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      label = json['label'] as String,
      prompt = json['prompt'] as String,
      responseType = json['responseType'] as String,
      note = json['note'] as String?,
      options = (json['options'] as List)
          .map(
            (item) =>
                CollegeReportOption.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      questions = (json['questions'] as List)
          .map(
            (item) =>
                CollegeReportQuestion.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false);
  final String id;
  final String label;
  final String prompt;
  final String responseType;
  final String? note;
  final List<CollegeReportOption> options;
  final List<CollegeReportQuestion> questions;
}

class CollegeReportTemplate {
  CollegeReportTemplate.fromJson(Map<String, dynamic> json)
    : version = json['version'] as int,
      title = json['title'] as String,
      instructions = json['instructions'] as String,
      sections = (json['sections'] as List)
          .map(
            (item) =>
                CollegeReportSection.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false);
  final int version;
  final String title;
  final String instructions;
  final List<CollegeReportSection> sections;
  Iterable<CollegeReportQuestion> get questions =>
      sections.expand((section) => section.questions);
}

class SavedCollegeReport {
  SavedCollegeReport.fromJson(Map<String, dynamic> json)
    : version = json['questionnaireVersion'] as int,
      answers = Map.unmodifiable({
        for (final item in json['answers'] as List)
          (item as Map<String, dynamic>)['questionKey'] as String:
              item['value'] as Object?,
      }),
      essay = json['essay'] as String,
      updatedAt = DateTime.parse(json['updatedAt'] as String);
  final int version;
  final Map<String, Object?> answers;
  final String essay;
  final DateTime updatedAt;
  int get answeredCount =>
      answers.values.where((value) => value != null).length;
}
