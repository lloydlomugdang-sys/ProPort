import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/screens/portfolio/portfolio_list_screen.dart';
import 'package:proport_app/screens/portfolio/portfolio_summary_screen.dart';
import 'package:proport_app/screens/portfolio/portfolio_export_screen.dart';
import 'package:proport_app/screens/portfolio/models/portfolio_models.dart';
import 'package:proport_app/screens/portfolio/widgets/export_option_card.dart';
import 'package:proport_app/screens/portfolio/widgets/section_counter_row.dart';
import 'package:proport_app/screens/portfolio/widgets/step_indicator.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/document_scope.dart';
import 'package:proport_app/services/document_service.dart';
import 'package:proport_app/services/portfolio_scope.dart';
import 'package:proport_app/services/portfolio_service.dart';
import 'package:proport_app/services/secure_token_store.dart';
import 'support/portfolio_export_test_support.dart';

void main() {
  testWidgets(
    'export errors are honest and duplicate generation is prevented',
    (tester) async {
      final auth = _FakePortfolioAuthService();
      final service = PortfolioService(authService: auth);
      final exporter = MemoryPortfolioExporter()
        ..pending = Completer<void>()
        ..fail = true;
      addTearDown(() {
        service.dispose();
        auth.dispose();
      });
      final info = PortfolioInfo.fromJson(
        _portfolioJson(id: 'saved-1', course: 'Course'),
      );
      await tester.pumpWidget(
        _app(
          service,
          auth,
          exporter: exporter,
          child: PortfolioExportScreen(portfolioInfo: info),
        ),
      );
      await tester.pumpAndSettle();
      final exportButton = find.text('Export Portfolio').last;
      await tester.ensureVisible(exportButton);
      final position = tester.getCenter(exportButton);
      await tester.tapAt(position);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const Key('portfolio-export-progress')),
        findsOneWidget,
      );
      await tester.tapAt(position);
      await tester.tap(find.text('DOCX Document'));
      await tester.pump();
      expect(exporter.generationCount, 1);
      expect(exporter.format, ExportFormat.pdf);
      exporter.pending!.complete();
      await tester.pumpAndSettle();
      expect(
        find.text('Unable to export the portfolio. Please try again.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('portfolio-export-success')), findsNothing);
      expect(find.text('Preview Portfolio'), findsNothing);
      expect(find.textContaining('private filesystem'), findsNothing);
      exporter
        ..pending = null
        ..fail = false;
      await tester.tap(find.text('Export Portfolio').last);
      await tester.pumpAndSettle();
      expect(find.text('Portfolio file created'), findsOneWidget);
      exporter.failShare = true;
      await tester.ensureVisible(find.text('Share'));
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Unable to share the file.'), findsOneWidget);
      expect(find.textContaining('private platform'), findsNothing);
      expect(find.text('Portfolio file created'), findsOneWidget);
      expect(auth.postCount, 0);
    },
  );

  testWidgets(
    'summary waits for real counts instead of showing a mock or zero fallback',
    (tester) async {
      final auth = _FakePortfolioAuthService()
        ..pendingDocuments = Completer<Map<String, dynamic>>();
      final service = PortfolioService(authService: auth);
      addTearDown(() {
        service.dispose();
        auth.dispose();
      });
      final record = PortfolioRecord.fromJson(
        _portfolioJson(id: 'saved-1', course: 'Course'),
      );
      await tester.pumpWidget(
        _app(service, auth, child: PortfolioSummaryScreen(portfolio: record)),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('portfolio-documents-loading')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('portfolio-total-items')), findsNothing);
      expect(find.text('Next'), findsNothing);
      auth.pendingDocuments!.complete(_documentsEnvelope([]));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('portfolio-total-items')))
            .data,
        '0',
      );
      expect(find.byType(SectionCounterRow), findsNWidgets(7));
      expect(find.text('Next'), findsOneWidget);
    },
  );

  for (final status in [401, 503]) {
    testWidgets(
      'document $status failure is safe and retry restores real summary',
      (tester) async {
        final auth = _FakePortfolioAuthService()
          ..failDocuments = true
          ..documentErrorStatus = status;
        final service = PortfolioService(authService: auth);
        addTearDown(() {
          service.dispose();
          auth.dispose();
        });
        final record = PortfolioRecord.fromJson(
          _portfolioJson(id: 'saved-1', course: 'Course'),
        );
        await tester.pumpWidget(
          _app(service, auth, child: PortfolioSummaryScreen(portfolio: record)),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('portfolio-documents-error')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('portfolio-total-items')), findsNothing);
        expect(find.text('Next'), findsNothing);
        auth.failDocuments = false;
        auth.serverDocuments.addAll(_documentFixtures());
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Text>(find.byKey(const Key('portfolio-total-items')))
              .data,
          '8',
        );
      },
    );
  }

  testWidgets(
    'PDF selection creates real PDF bytes, shares, and continues to preview',
    (tester) async {
      final auth = _FakePortfolioAuthService();
      final service = PortfolioService(authService: auth);
      final exporter = MemoryPortfolioExporter();
      addTearDown(() {
        service.dispose();
        auth.dispose();
      });
      final info = PortfolioInfo.fromJson(
        _portfolioJson(id: 'saved-1', course: 'Saved Course'),
      );
      await tester.pumpWidget(
        _app(
          service,
          auth,
          exporter: exporter,
          child: PortfolioExportScreen(portfolioInfo: info),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<ExportOptionCard>(find.byType(ExportOptionCard))
            .singleWhere((card) => card.isSelected)
            .format,
        ExportFormat.pdf,
      );
      await tester.ensureVisible(find.text('Export Portfolio').last);
      await tester.tap(find.text('Export Portfolio').last);
      await tester.pumpAndSettle();
      expect(find.text('Portfolio file created'), findsOneWidget);
      expect(ascii.decode(exporter.bytes!.take(5).toList()), '%PDF-');
      expect(exporter.bytes!.length, greaterThan(1000));
      expect(exporter.format, ExportFormat.pdf);
      await tester.ensureVisible(find.text('Share'));
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(exporter.shareCount, 1);
      await tester.ensureVisible(find.text('Preview Portfolio'));
      await tester.tap(find.text('Preview Portfolio'));
      await tester.pumpAndSettle();
      expect(find.text('Portfolio Preview'), findsOneWidget);
      expect(find.text('Saved Course'), findsOneWidget);
      expect(find.text('Portfolio Student'), findsOneWidget);
      expect(find.text('No stored documents to include yet.'), findsOneWidget);
      expect(find.text('Portfolio Exported'), findsNothing);
      expect(auth.postCount, 0);
      // With no history route underneath, the same My Portfolios screen is opened.
      await tester.tap(find.text('My Portfolios'));
      await tester.pumpAndSettle();
      expect(find.byType(PortfolioListScreen), findsOneWidget);
    },
  );

  testWidgets('shows loading then an honest empty portfolio state', (
    tester,
  ) async {
    final auth = _FakePortfolioAuthService();
    auth.pendingList = Completer<Map<String, dynamic>>();
    final service = PortfolioService(authService: auth);
    addTearDown(() {
      service.dispose();
      auth.dispose();
    });

    await tester.pumpWidget(_app(service, auth));
    await tester.pump();
    expect(find.byKey(const Key('portfolio-loading')), findsOneWidget);

    auth.pendingList!.complete(_envelope({'portfolios': <Object>[]}));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('portfolio-empty')), findsOneWidget);
    expect(find.text('No portfolios yet.'), findsOneWidget);
    expect(find.text('John Dela Cruz'), findsNothing);
  });

  testWidgets('loads, views, and edits a persisted portfolio immediately', (
    tester,
  ) async {
    final auth = _FakePortfolioAuthService([
      _portfolioJson(id: 'portfolio-1', course: 'Original Course'),
    ]);
    final service = PortfolioService(authService: auth);
    addTearDown(() {
      service.dispose();
      auth.dispose();
    });

    await tester.pumpWidget(_app(service, auth));
    await tester.pumpAndSettle();

    expect(find.text('Portfolio Student'), findsOneWidget);
    expect(find.textContaining('Original Course'), findsOneWidget);
    expect(find.text('Monday 8:00 AM - 10:00 AM'), findsOneWidget);

    await tester.tap(find.byKey(const Key('view-portfolio-1')));
    await tester.pumpAndSettle();
    expect(auth.itemGetCount, 1);
    expect(find.text('Portfolio Preview'), findsOneWidget);
    expect(find.text('Portfolio Student'), findsWidgets);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('edit-portfolio-1')));
    await tester.pumpAndSettle();
    expect(find.text('Edit Portfolio'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(4), 'Updated Course');
    final saveButton = find.text('Save Changes');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(auth.patchCount, 1);
    expect(find.textContaining('Updated Course'), findsOneWidget);
    expect(find.text('Portfolio updated successfully.'), findsOneWidget);
  });

  testWidgets('creates and deletes a portfolio through the existing form flow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final auth = _FakePortfolioAuthService()
      ..serverDocuments.addAll(_documentFixtures());
    final service = PortfolioService(authService: auth);
    final exporter = MemoryPortfolioExporter();
    addTearDown(() {
      service.dispose();
      auth.dispose();
    });

    await tester.pumpWidget(_app(service, auth, exporter: exporter));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Portfolio'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'New Portfolio Student');
    await tester.enterText(fields.at(1), '3BSIT-2');
    await tester.enterText(fields.at(2), 'Professor New');
    await tester.enterText(fields.at(3), 'Mobile Development');

    await tester.ensureVisible(find.byKey(const Key('schedule-day')));
    await tester.tap(find.byKey(const Key('schedule-day')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Friday').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('schedule-start-time')));
    await tester.tap(find.byKey(const Key('schedule-start-time')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('schedule-end-time')));
    await tester.tap(find.byKey(const Key('schedule-end-time')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final nextButton = find.text('Next');
    await tester.ensureVisible(nextButton);
    await tester.tap(nextButton);
    await tester.pumpAndSettle();

    expect(auth.postCount, 1);
    expect(find.text('Portfolio Summary'), findsOneWidget);
    expect(find.text('Total Items'), findsOneWidget);
    expect(find.text('Sections Included'), findsOneWidget);
    expect(
      tester
          .widget<StepIndicatorLight>(find.byType(StepIndicatorLight))
          .currentStep,
      2,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('portfolio-total-items'))).data,
      '8',
    );
    final counts = {
      for (final row in tester.widgetList<SectionCounterRow>(
        find.byType(SectionCounterRow),
      ))
        row.name: row.count,
    };
    expect(counts, {
      'Creative Title': 1,
      'Curriculum Vitae': 1,
      'Scholastic Record': 1,
      'Certificates': 2,
      'Accomplishments': 1,
      'Other Achievements': 1,
      'College Report': 1,
    });
    expect(find.text('Friday 8:00 AM - 9:00 AM'), findsOneWidget);

    // Returning to Title Page updates the same persisted record, never creates a duplicate.
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();
    expect(find.text('Title Page'), findsOneWidget);
    expect(
      tester
          .widget<StepIndicatorLight>(find.byType(StepIndicatorLight))
          .currentStep,
      1,
    );
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(auth.postCount, 1);
    expect(auth.patchCount, 1);
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.byType(PortfolioExportScreen), findsOneWidget);
    expect(
      tester
          .widget<StepIndicatorLight>(find.byType(StepIndicatorLight))
          .currentStep,
      3,
    );
    expect(find.text('PDF Document'), findsOneWidget);
    expect(find.text('DOCX Document'), findsOneWidget);
    await tester.tap(find.text('DOCX Document'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<ExportOptionCard>(find.byType(ExportOptionCard))
          .singleWhere((card) => card.isSelected)
          .format,
      ExportFormat.docx,
    );
    await tester.ensureVisible(find.text('Export Portfolio').last);
    await tester.tap(find.text('Export Portfolio').last);
    await tester.pumpAndSettle();
    expect(find.text('Portfolio file created'), findsOneWidget);
    expect(exporter.format, ExportFormat.docx);
    final zip = ZipDecoder().decodeBytes(exporter.bytes!);
    final xml = utf8.decode(zip.findFile('word/document.xml')!.content);
    expect(xml, contains('New Portfolio Student'));
    expect(xml, contains('Stored Training One'));
    // The fixture's public filename contains its ID; no standalone ID is emitted.
    expect(xml, isNot(contains('>training-1<')));
    expect(xml, isNot(contains('ownerId')));
    expect(xml, isNot(contains('accessToken')));
    expect(exporter.generationCount, 1);
    expect(auth.postCount, 1); // Export does not create another portfolio.
    await tester.ensureVisible(find.text('Preview Portfolio'));
    await tester.tap(find.text('Preview Portfolio'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('preview-document-training-1')),
      findsOneWidget,
    );
    expect(find.text('Stored Training One'), findsOneWidget);
    expect(find.text('A saved description'), findsWidgets);
    expect(find.text('My own reflection'), findsWidgets);
    expect(find.text('Generated format: DOCX Document'), findsOneWidget);
    expect(find.text('Portfolio Preview'), findsOneWidget);
    expect(find.text('Confirm & Export'), findsNothing);
    expect(find.text('Portfolio Exported'), findsNothing);
    await tester.tap(find.text('My Portfolios'));
    await tester.pumpAndSettle();

    expect(find.text('My Portfolios'), findsOneWidget);
    expect(find.text('Portfolio Preview'), findsNothing);
    expect(find.text('New Portfolio Student'), findsOneWidget);
    expect(find.text('Friday 8:00 AM - 9:00 AM'), findsOneWidget);
    // A new service instance restores the same server record after restart.
    await tester.pumpWidget(const SizedBox.shrink());
    final restored = PortfolioService(authService: auth);
    final restoredExporter = MemoryPortfolioExporter();
    await tester.pumpWidget(_app(restored, auth, exporter: restoredExporter));
    await tester.pumpAndSettle();
    expect(restored.portfolios.single.id, 'portfolio-1');
    await restored.loadPortfolios(force: true);
    await tester.pumpAndSettle();
    expect(restored.portfolios, hasLength(1));
    await tester.tap(find.byKey(const Key('view-portfolio-1')));
    await tester.pumpAndSettle();
    expect(find.text('Portfolio Preview'), findsOneWidget);
    expect(
      find.byKey(const Key('preview-document-training-1')),
      findsOneWidget,
    );
    expect(auth.documentGetCount, greaterThanOrEqualTo(3));
    // A reopened saved record can export again without another create request.
    await tester.tap(find.text('Export Portfolio'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Export Portfolio').last);
    await tester.tap(find.text('Export Portfolio').last);
    await tester.pumpAndSettle();
    expect(restoredExporter.generationCount, 1);
    expect(auth.postCount, 1);
    await tester.ensureVisible(find.text('Preview Portfolio'));
    await tester.tap(find.text('Preview Portfolio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My Portfolios'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-portfolio-1')));
    await tester.pumpAndSettle();
    expect(find.text('Delete Portfolio'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(auth.deleteCount, 1);
    expect(find.byKey(const Key('portfolio-empty')), findsOneWidget);
    expect(find.text('Portfolio deleted successfully.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    restored.dispose();
  });

  testWidgets('shows a safe API error when loading fails', (tester) async {
    final auth = _FakePortfolioAuthService()..failList = true;
    final service = PortfolioService(authService: auth);
    addTearDown(() {
      service.dispose();
      auth.dispose();
    });

    await tester.pumpWidget(_app(service, auth));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('portfolio-error')), findsOneWidget);
    expect(find.text('Portfolio service is unavailable.'), findsOneWidget);
  });
}

Widget _app(
  PortfolioService service,
  _FakePortfolioAuthService auth, {
  Widget child = const PortfolioListScreen(),
  MemoryPortfolioExporter? exporter,
}) {
  final documents = DocumentService(authService: auth);
  addTearDown(documents.dispose);
  return DocumentScope(
    documentService: documents,
    child: PortfolioScope(
      portfolioService: service,
      exporter: exporter ?? MemoryPortfolioExporter(),
      child: MaterialApp(
        onGenerateRoute: (settings) =>
            MaterialPageRoute<void>(settings: settings, builder: (_) => child),
        onGenerateInitialRoutes: (_) => [
          MaterialPageRoute<void>(
            settings: RouteSettings(
              name: child is PortfolioListScreen
                  ? PortfolioListScreen.routeName
                  : '/',
            ),
            builder: (_) => child,
          ),
        ],
      ),
    ),
  );
}

class _FakePortfolioAuthService extends AuthService {
  _FakePortfolioAuthService([List<Map<String, dynamic>> initial = const []])
    : serverPortfolios = initial.map(Map<String, dynamic>.from).toList(),
      super(tokenStore: _EmptyTokenStore());

  final List<Map<String, dynamic>> serverPortfolios;
  Completer<Map<String, dynamic>>? pendingList;
  bool failList = false;
  bool failDocuments = false;
  int documentErrorStatus = 503;
  Completer<Map<String, dynamic>>? pendingDocuments;
  final List<Map<String, dynamic>> serverDocuments = [];
  int documentGetCount = 0;
  int itemGetCount = 0;
  int postCount = 0;
  int patchCount = 0;
  int deleteCount = 0;

  @override
  Future<Map<String, dynamic>> authenticatedGetJson(String path) async {
    if (path == '/api/v1/documents/categories') {
      return _envelope({
        'categories': [
          {
            'key': 'certificates',
            'name': 'Certificates',
            'folders': [
              {'key': 'creative-title', 'name': 'Creative Title'},
              {'key': 'trainings', 'name': 'Trainings'},
            ],
          },
        ],
      });
    }
    if (path == '/api/v1/documents') {
      documentGetCount++;
      if (pendingDocuments != null) return pendingDocuments!.future;
      if (failDocuments) {
        throw ApiException(
          code: documentErrorStatus == 401
              ? 'UNAUTHORIZED'
              : 'DOCUMENT_UNAVAILABLE',
          message: 'Documents are unavailable.',
          statusCode: documentErrorStatus,
        );
      }
      return _documentsEnvelope(serverDocuments);
    }
    if (path == '/api/v1/portfolios') {
      if (pendingList != null) return pendingList!.future;
      if (failList) {
        throw const ApiException(
          code: 'PORTFOLIO_UNAVAILABLE',
          message: 'Portfolio service is unavailable.',
          statusCode: 503,
        );
      }
      return _envelope({'portfolios': serverPortfolios});
    }
    itemGetCount++;
    final id = path.split('/').last;
    return _envelope({
      'portfolio': serverPortfolios.singleWhere(
        (portfolio) => portfolio['id'] == id,
      ),
    });
  }

  @override
  Future<Map<String, dynamic>> authenticatedPostJson(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    postCount++;
    expect(path, '/api/v1/portfolios');
    expect(body, isNot(contains('ownerId')));
    final portfolio = {
      'id': 'portfolio-${serverPortfolios.length + 1}',
      ...body,
      'createdAt': '2026-09-01T00:00:00.000Z',
      'updatedAt': '2026-09-01T00:00:00.000Z',
    };
    serverPortfolios.insert(0, portfolio);
    return _envelope({'portfolio': portfolio});
  }

  @override
  Future<Map<String, dynamic>> authenticatedPatchJson(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    patchCount++;
    expect(body, isNot(contains('ownerId')));
    final id = path.split('/').last;
    final index = serverPortfolios.indexWhere(
      (portfolio) => portfolio['id'] == id,
    );
    final updated = {
      ...serverPortfolios[index],
      ...body,
      'updatedAt': '2026-09-02T00:00:00.000Z',
    };
    serverPortfolios[index] = updated;
    return _envelope({'portfolio': updated});
  }

  @override
  Future<Map<String, dynamic>> authenticatedDeleteJson(String path) async {
    deleteCount++;
    final id = path.split('/').last;
    serverPortfolios.removeWhere((portfolio) => portfolio['id'] == id);
    return _envelope({'status': 'deleted', 'portfolioId': id});
  }
}

class _EmptyTokenStore implements SecureTokenStore {
  @override
  Future<void> deleteRefreshToken() async {}

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> writeRefreshToken(String refreshToken) async {}
}

Map<String, dynamic> _portfolioJson({
  required String id,
  required String course,
}) => {
  'id': id,
  'fullName': 'Portfolio Student',
  'yearAndSection': '4BSIT-1',
  'schedule': 'Monday 8:00 AM - 10:00 AM',
  'instructorName': 'Professor Example',
  'course': course,
  'courseCode': 'CCSFE4-18',
  'semesterAndYear': '2nd Semester, A.Y. 2025-2026',
  'createdAt': '2026-09-01T00:00:00.000Z',
  'updatedAt': '2026-09-01T00:00:00.000Z',
};

Map<String, dynamic> _envelope(Map<String, dynamic> data) => {
  'data': data,
  'meta': {'requestId': 'portfolio-widget-test'},
};

List<Map<String, dynamic>> _documentFixtures() => [
  _document('creative', 'certificates', 'creative-title', 'Certificate Cover'),
  _document('cv', 'curriculum-vitae', 'curriculum-vitae', 'My CV'),
  _document(
    'tor',
    'scholastic-record',
    'unofficial-tor-with-reflections',
    'My Transcript',
  ),
  _document('training-1', 'certificates', 'trainings', 'Stored Training One'),
  _document('training-2', 'certificates', 'trainings', 'Stored Training Two'),
  _document('project', 'accomplishments', 'projects', 'Mobile Project'),
  _document(
    'achievement',
    'other-achievements',
    'projects',
    'Academic Achievement',
  ),
  _document(
    'report',
    'college-report',
    'college-report',
    'College Report Document',
  ),
];

Map<String, dynamic> _document(
  String id,
  String category,
  String folder,
  String title,
) => {
  'id': id,
  'categoryKey': category,
  'folderKey': folder,
  'title': title,
  'documentDate': '2026-09-14',
  'description': 'A saved description',
  'reflection': 'My own reflection',
  'originalFileName': '$id.pdf',
  'mimeType': 'application/pdf',
  'fileKind': 'pdf',
  'extension': 'pdf',
  'sizeBytes': 128,
  'createdAt': '2026-09-14T00:00:00Z',
  'updatedAt': '2026-09-14T00:00:00Z',
};

Map<String, dynamic> _documentsEnvelope(List<Map<String, dynamic>> documents) {
  final categoryCounts = <String, int>{};
  final folderCounts = <String, int>{};
  for (final document in documents) {
    final category = document['categoryKey'] as String;
    final folder = '$category/${document['folderKey']}';
    categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
    folderCounts[folder] = (folderCounts[folder] ?? 0) + 1;
  }
  return _envelope({
    'documents': documents,
    'summary': {
      'totalCount': documents.length,
      'categoryCounts': categoryCounts,
      'folderCounts': folderCounts,
    },
  });
}
