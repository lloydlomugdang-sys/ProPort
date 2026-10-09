import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/screens/portfolio/models/portfolio_document_order.dart';
import 'package:proport_app/screens/portfolio/models/portfolio_models.dart';
import 'package:proport_app/screens/portfolio/portfolio_preview_screen.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/document_models.dart';
import 'package:proport_app/services/document_scope.dart';
import 'package:proport_app/services/document_service.dart';
import 'package:proport_app/services/portfolio_export_service.dart';
import 'package:proport_app/services/secure_token_store.dart';
import 'support/portfolio_export_test_support.dart';

const _info = PortfolioInfo(
  fullName: 'Portfolio Student',
  yearAndSection: 'Fourth Year',
  schedule: 'Monday',
  instructorName: 'Instructor',
);

final _documents = [
  for (final pair in [
    ['college-report', 'college-report'],
    ['other-achievements', 'projects'],
    ['accomplishments', 'assessments'],
    ['accomplishments', 'projects'],
    ['accomplishments', 'case-studies'],
    ['accomplishments', 'thesis-capstone'],
    ['certificates', 'trainings'],
    ['certificates', 'other-seminars'],
    ['certificates', 'seminars'],
    ['scholastic-record', 'unofficial-tor-with-reflections'],
    ['curriculum-vitae', 'curriculum-vitae'],
    ['certificates', 'creative-title'],
  ])
    {
      'id': '${pair[0]}-${pair[1]}',
      'categoryKey': pair[0],
      'folderKey': pair[1],
      'title': 'Evidence ${pair[0]} ${pair[1]}',
      'documentDate': '2026-01-01',
      'createdAt': '2026-01-01',
      'updatedAt': '2026-01-01',
      'originalFileName': 'evidence.pdf',
      'mimeType': 'application/pdf',
      'fileKind': 'pdf',
      'extension': 'pdf',
      'sizeBytes': 100,
    },
];

final _categories = [
  {
    'key': 'certificates',
    'name': 'Certificates',
    'folders': [
      for (final key in [
        'creative-title',
        'seminars',
        'other-seminars',
        'trainings',
      ])
        {'key': key, 'name': key},
    ],
  },
  {
    'key': 'accomplishments',
    'name': 'Accomplishments',
    'folders': [
      for (final key in [
        'creative-title',
        'thesis-capstone',
        'case-studies',
        'projects',
        'assessments',
      ])
        {'key': key, 'name': key},
    ],
  },
];

class _Tokens implements SecureTokenStore {
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> writeRefreshToken(String value) async {}
  @override
  Future<void> deleteRefreshToken() async {}
}

class _Auth extends AuthService {
  _Auth() : super(tokenStore: _Tokens());
  @override
  Future<Map<String, dynamic>> authenticatedGetJson(String path) async => {
    'data': path.endsWith('/categories')
        ? {'categories': _categories}
        : {
            'documents': _documents,
            'summary': {
              'totalCount': 12,
              'categoryCounts': {
                'curriculum-vitae': 1,
                'scholastic-record': 1,
                'certificates': 4,
                'accomplishments': 4,
                'other-achievements': 1,
                'college-report': 1,
              },
              'folderCounts': {'certificates/creative-title': 1},
            },
          },
  };
}

void main() {
  test(
    'portfolio presentation respects seeded subgroup order independent of upload order',
    () {
      final ordered = PortfolioDocumentOrder.sorted(
        _documents.map(DocumentRecord.fromJson).toList(),
        _categories.map(DocumentCategory.fromJson).toList(),
      );
      expect(ordered.map((d) => d.folderKey), [
        'creative-title',
        'curriculum-vitae',
        'unofficial-tor-with-reflections',
        'seminars',
        'other-seminars',
        'trainings',
        'thesis-capstone',
        'case-studies',
        'projects',
        'assessments',
        'projects',
        'college-report',
      ]);
      final unknown = DocumentRecord.fromJson({
        ..._documents.first,
        'categoryKey': 'unknown',
        'folderKey': 'creative-title',
      });
      expect(PortfolioDocumentOrder.sectionFor(unknown), 'unknown');
    },
  );

  test(
    'metadata outline uses the same stable document/subsection order without changing PDF transport',
    () async {
      final auth = _Auth();
      final service = DocumentService(authService: auth);
      addTearDown(service.dispose);
      addTearDown(auth.dispose);
      await service.load();
      final content = PortfolioExportContent.fromDocuments(_info, service);
      expect(content.sections.first.name, 'Creative Title');
      expect(content.sections.last.name, 'College Report');
      expect(content.sections.first.documents, hasLength(1));
      expect(
        content.sections
            .firstWhere((s) => s.name == 'Certificates')
            .documents
            .map((d) => d['Folder']),
        ['seminars', 'other-seminars', 'trainings'],
      );
    },
  );

  testWidgets(
    'preview places actual Creative Title before the contents indicator and all major sections in official order',
    (tester) async {
      final auth = _Auth();
      final service = DocumentService(authService: auth);
      addTearDown(service.dispose);
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        DocumentScope(
          documentService: service,
          child: MaterialApp(
            home: PortfolioPreviewScreen(
              portfolioInfo: _info,
              exporter: MemoryPortfolioExporter(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ordered = PortfolioDocumentOrder.sorted(
        service.documents,
        service.categories,
      );
      double previousY = tester.getTopLeft(find.text('Standard Title')).dy;
      for (final document in ordered) {
        final finder = find.byKey(ValueKey('preview-document-${document.id}'));
        expect(finder, findsOneWidget);
        final y = tester.getTopLeft(finder).dy;
        expect(y, greaterThan(previousY));
        previousY = y;
      }
      final creativeY = tester
          .getTopLeft(
            find.byKey(
              const ValueKey('preview-document-certificates-creative-title'),
            ),
          )
          .dy;
      final indicatorY = tester.getTopLeft(find.text('Sections Included')).dy;
      final cvY = tester
          .getTopLeft(
            find.byKey(
              const ValueKey(
                'preview-document-curriculum-vitae-curriculum-vitae',
              ),
            ),
          )
          .dy;
      expect(creativeY, lessThan(indicatorY));
      expect(indicatorY, lessThan(cvY));
      expect(find.text('NEW ERA UNIVERSITY'), findsNothing);
      expect(
        find.text("Unofficial TOR - Bachelor's Degree with Reflection"),
        findsNWidgets(2),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
