import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/portfolio_service.dart';
import 'package:proport_app/services/portfolio_scope.dart';
import 'package:proport_app/services/portfolio_template.dart';
import 'package:proport_app/services/document_models.dart';
import 'package:proport_app/services/document_service.dart';
import 'package:proport_app/services/document_scope.dart';
import 'package:proport_app/screens/portfolio/models/portfolio_models.dart';
import 'package:proport_app/screens/portfolio/models/portfolio_document_order.dart';
import 'package:proport_app/screens/portfolio/portfolio_summary_screen.dart';
import 'package:proport_app/screens/portfolio/portfolio_export_screen.dart';
import 'support/portfolio_template_test_support.dart';

Map<String, dynamic> _record() => {
  'id': 'saved',
  'fullName': 'Student',
  'yearAndSection': '4A',
  'schedule': 'Monday 9:00 AM - 10:00 AM',
  'instructorName': 'Instructor',
  'course': 'Portfolio',
  'courseCode': 'P401',
  'semesterAndYear': '1st Semester, A.Y. 2026-2027',
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': '2026-01-01T00:00:00Z',
};

class _Auth extends AuthService {
  Map<String, dynamic> configuration = portfolioTemplateJson();
  Map<String, dynamic> record = _record();
  int reads = 0;
  bool fail = false;
  Map<String, dynamic>? patch;
  @override
  Future<Map<String, dynamic>> authenticatedGetJson(String path) async {
    if (path.endsWith('/template')) {
      reads++;
      if (fail) {
        throw const ApiException(
          code: 'NETWORK_ERROR',
          message: 'Please retry.',
        );
      }
      return {
        'data': {'template': configuration},
      };
    }
    if (path.endsWith('/categories')) {
      return {
        'data': {'categories': <Object>[]},
      };
    }
    return {
      'data': {
        'documents': <Object>[],
        'summary': {
          'totalCount': 0,
          'categoryCounts': <String, int>{},
          'folderCounts': <String, int>{},
        },
      },
    };
  }

  @override
  Future<Map<String, dynamic>> authenticatedPatchJson(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    patch = body;
    record = {...record, ...body};
    return {
      'data': {'portfolio': record},
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'effective configuration is fetched once, shared, force refreshed; failures never use an invented fallback',
    () async {
      final auth = _Auth();
      addTearDown(auth.dispose);
      final own = PortfolioService(authService: auth);
      addTearDown(own.dispose);
      final result = await Future.wait([
        own.loadTemplate(),
        own.loadTemplate(),
      ]);
      expect(result[0], same(result[1]));
      expect(auth.reads, 1);
      await own.loadTemplate();
      expect(auth.reads, 1);
      auth.configuration = {...auth.configuration, 'version': 2};
      expect((await own.loadTemplate(force: true)).version, 2);
      auth.fail = true;
      await expectLater(
        own.loadTemplate(force: true),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'preview order, disabled sections, title rules and display labels all come from server configuration',
    () {
      final json = portfolioTemplateJson();
      final sections = json['sections'] as List;
      final cert =
          sections.firstWhere((s) => s['key'] == 'certificates')
              as Map<String, dynamic>;
      cert.addAll({
        'order': 0,
        'label': 'Approved Awards',
        'generateCreativeTitle': false,
        'required': true,
      });
      (sections.firstWhere((s) => s['key'] == 'scholastic-record')
              as Map)['enabled'] =
          false;
      final template = PortfolioTemplate.fromJson(json);
      DocumentRecord doc(String key, String folder) => DocumentRecord.fromJson({
        'id': '$key-$folder',
        'categoryKey': key,
        'folderKey': folder,
        'title': 'Evidence',
        'documentDate': '2026-01-01',
        'originalFileName': 'file.pdf',
        'mimeType': 'application/pdf',
        'fileKind': 'pdf',
        'extension': 'pdf',
        'sizeBytes': 1,
        'createdAt': '2026-01-01',
        'updatedAt': '2026-01-01',
      });
      final order = PortfolioDocumentOrder.sorted(
        [
          doc('curriculum-vitae', 'curriculum-vitae'),
          doc('certificates', 'creative-title'),
          doc('scholastic-record', 'unofficial-tor-with-reflections'),
          doc('certificates', 'trainings'),
        ],
        [],
        template,
      );
      expect(order.map((d) => d.categoryKey), [
        'certificates',
        'curriculum-vitae',
      ]);
      expect(
        PortfolioDocumentOrder.sectionFor(order.first, template),
        'Approved Awards',
      );
      expect(template.section('certificates')!.required, isTrue);
      final summary = PortfolioSummary.fromDocumentSummary(
        const DocumentSummary(
          totalCount: 4,
          categoryCounts: {
            'certificates': 2,
            'curriculum-vitae': 1,
            'scholastic-record': 1,
          },
          folderCounts: {'certificates/creative-title': 1},
        ),
        template,
      );
      expect(summary.totalItems, 2);
      expect(summary.sections[1].name, 'Approved Awards');
    },
  );

  test(
    'legacy title pages remain valid and saved section text survives serialization and clear',
    () async {
      final legacy = PortfolioInfo.fromJson(_record());
      expect(legacy.creativeTitles, isEmpty);
      final manual = legacy.copyWith(
        creativeTitles: {'certificates': 'My milestones'},
      );
      expect(
        PortfolioInfo.fromJson(manual.toMap()).creativeTitles,
        manual.creativeTitles,
      );
      expect(manual.validationErrors, isEmpty);
      final auth = _Auth();
      final service = PortfolioService(authService: auth);
      addTearDown(auth.dispose);
      addTearDown(service.dispose);
      expect(
        (await service.saveCreativeTitles(
          'saved',
          manual.creativeTitles,
        )).info.creativeTitles,
        manual.creativeTitles,
      );
      expect(auth.patch!.keys, ['creativeTitles']);
      expect(
        (await service.saveCreativeTitles('saved', {})).info.creativeTitles,
        isEmpty,
      );
    },
  );

  testWidgets(
    'student saves optional section title without upload; Next uses saved text at 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = _Auth();
      final service = PortfolioService(authService: auth),
          documents = DocumentService(authService: auth);
      addTearDown(auth.dispose);
      addTearDown(service.dispose);
      addTearDown(documents.dispose);
      await tester.pumpWidget(
        PortfolioScope(
          portfolioService: service,
          child: DocumentScope(
            documentService: documents,
            child: MaterialApp(
              home: PortfolioSummaryScreen(
                portfolio: PortfolioRecord.fromJson(auth.record),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Edit Section Creative Titles'));
      await tester.tap(find.text('Edit Section Creative Titles'));
      await tester.pumpAndSettle();
      final title = find.byKey(const ValueKey('creative-title-certificates'));
      await tester.ensureVisible(title);
      await tester.enterText(title, 'My milestones');
      await tester.ensureVisible(find.text('Save Creative Titles'));
      await tester.tap(find.text('Save Creative Titles'));
      await tester.pumpAndSettle();
      expect(
        (auth.patch!['creativeTitles'] as Map)['certificates'],
        'My milestones',
      );
      await tester.ensureVisible(find.text('Next'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PortfolioExportScreen>(find.byType(PortfolioExportScreen))
            .portfolioInfo
            .creativeTitles['certificates'],
        'My milestones',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
