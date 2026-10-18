import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/services/scholastic_details.dart';

void main() {
  test(
    'study year and semester round trip without claiming full degree coverage',
    () {
      const details = ScholasticDetails(
        studyYear: 2,
        semester: '1st Semester',
        reflectionIncluded: true,
      );
      final restored = ScholasticDetails.fromJson(details.toJson());
      expect(restored.period, 'Year 2 / 1st Semester');
      final coverage = const ScholasticCoverage().adjust(restored, null, 1);
      expect(coverage.periodCounts, {'Year 2 / 1st Semester': 1});
      expect(coverage.missingReflection, 0);
      expect(coverage.missingPeriod, 0);
      expect(coverage.isComplete, isFalse);
      expect(coverage.adjust(restored, null, -1).periodCounts, isEmpty);
    },
  );
  test('reflection requires explicit checkbox or actual written text', () {
    const details = ScholasticDetails();
    expect(details.reflectionSatisfied(null), isFalse);
    expect(details.reflectionSatisfied('  '), isFalse);
    expect(details.reflectionSatisfied('My reflection'), isTrue);
    expect(
      const ScholasticDetails(
        reflectionIncluded: true,
      ).reflectionSatisfied(null),
      isTrue,
    );
    final coverage = const ScholasticCoverage().adjust(null, '', 1);
    expect(coverage.missingReflection, 1);
    expect(coverage.missingPeriod, 1);
  });
}
