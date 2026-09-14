import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/screens/portfolio/models/portfolio_models.dart';
import 'package:proport_app/services/document_models.dart';

void main() {
  test(
    'portfolio counts use server totals and separate creative titles without double counting',
    () {
      final summary = PortfolioSummary.fromDocumentSummary(
        const DocumentSummary(
          totalCount: 145,
          categoryCounts: {
            'certificates': 110,
            'curriculum-vitae': 10,
            'scholastic-record': 20,
            'college-report': 5,
          },
          folderCounts: {
            'certificates/creative-title': 10,
            'curriculum-vitae/creative-title': 2,
          },
        ),
      );
      expect(summary.totalItems, 145);
      expect(summary.sections.map((section) => section.count), [
        12,
        8,
        20,
        100,
        0,
        0,
        5,
      ]);
      expect(
        summary.sections.fold<int>(0, (sum, section) => sum + section.count),
        145,
      );
    },
  );

  test('a known empty collection shows all seven sections with zero items', () {
    final summary = PortfolioSummary.fromDocumentSummary(DocumentSummary.empty);
    expect(summary.totalItems, 0);
    expect(summary.sections, hasLength(7));
    expect(summary.sections.every((section) => section.count == 0), isTrue);
  });
}
