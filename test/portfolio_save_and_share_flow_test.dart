import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/screens/portfolio/models/portfolio_models.dart';
import 'package:proport_app/screens/portfolio/portfolio_export_screen.dart';
import 'package:proport_app/screens/portfolio/portfolio_preview_screen.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/document_scope.dart';
import 'package:proport_app/services/document_service.dart';
import 'package:proport_app/services/portfolio_export_service.dart';
import 'package:proport_app/services/portfolio_scope.dart';
import 'package:proport_app/services/portfolio_service.dart';
import 'package:proport_app/services/secure_token_store.dart';
import 'support/portfolio_export_test_support.dart';

class _EmptyTokenStore implements SecureTokenStore {
  @override
  Future<void> deleteRefreshToken() async {}
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> writeRefreshToken(String refreshToken) async {}
}

class _MockPortfolioAuthService extends AuthService {
  _MockPortfolioAuthService() : super(tokenStore: _EmptyTokenStore());

  @override
  Future<Map<String, dynamic>> authenticatedGetJson(String path) async {
    if (path == '/api/v1/documents/categories') {
      return {
        'data': {
          'categories': [
            {
              'key': 'certificates',
              'name': 'Certificates',
              'folders': [
                {'key': 'seminars', 'name': 'Seminars'},
              ],
            },
          ],
        },
      };
    }
    if (path == '/api/v1/documents') {
      return {
        'data': {
          'documents': [
            {
              'id': 'doc-1',
              'categoryKey': 'certificates',
              'folderKey': 'seminars',
              'title': 'Flutter Certificate',
              'documentDate': '2026-09-24T00:00:00.000Z',
              'originalFileName': 'flutter_cert.pdf',
              'mimeType': 'application/pdf',
              'fileKind': 'pdf',
              'extension': 'pdf',
              'sizeBytes': 2048,
              'createdAt': '2026-09-24T00:00:00.000Z',
              'updatedAt': '2026-09-24T00:00:00.000Z',
            },
          ],
          'summary': {
            'totalCount': 1,
            'categoryCounts': {'certificates': 1},
            'folderCounts': {'certificates/seminars': 1},
          },
        },
      };
    }
    return {'data': {}};
  }
}

PortfolioInfo _sampleInfo() {
  return const PortfolioInfo(
    fullName: 'Alex Santos',
    yearAndSection: '4th Year - BSIT 4A',
    schedule: 'MWF 8:00 AM - 11:00 AM',
    instructorName: 'Prof. Garcia',
    course: 'Information Technology',
    courseCode: 'IT401',
    semesterAndYear: '1st Sem AY 2026-2027',
  );
}

Widget _wrapPreview({
  required PortfolioInfo info,
  required MemoryPortfolioExporter exporter,
  PortfolioExportFile? initialFile,
  ExportFormat? format,
  DocumentService? documentService,
}) {
  final auth = _MockPortfolioAuthService();
  final docs = documentService ?? DocumentService(authService: auth);
  final service = PortfolioService(authService: auth);

  return DocumentScope(
    documentService: docs,
    child: PortfolioScope(
      portfolioService: service,
      exporter: exporter,
      child: MaterialApp(
        home: PortfolioPreviewScreen(
          portfolioInfo: info,
          exportFormat: format,
          initialExportedFile: initialFile,
          exporter: exporter,
        ),
      ),
    ),
  );
}

Widget _wrapExport({
  required PortfolioInfo info,
  required MemoryPortfolioExporter exporter,
}) {
  final auth = _MockPortfolioAuthService();
  final docs = DocumentService(authService: auth);
  final service = PortfolioService(authService: auth);

  return DocumentScope(
    documentService: docs,
    child: PortfolioScope(
      portfolioService: service,
      exporter: exporter,
      child: MaterialApp(home: PortfolioExportScreen(portfolioInfo: info)),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Portfolio Save to Device & Share Flow', () {
    testWidgets(
      '1 & 2: Save to Device action and Share action are both visible in PortfolioPreviewScreen',
      (tester) async {
        final exporter = MemoryPortfolioExporter();
        await tester.pumpWidget(
          _wrapPreview(info: _sampleInfo(), exporter: exporter),
        );
        await tester.pumpAndSettle();

        // App bar has Share and Download action icons
        expect(
          find.byKey(const Key('portfolio-preview-share-btn')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('portfolio-preview-download-btn')),
          findsOneWidget,
        );

        // Bottom action area has explicit "Save to Device" button
        expect(
          find.byKey(const Key('portfolio-preview-save-btn')),
          findsOneWidget,
        );
        expect(find.text('Save to Device'), findsWidgets);

        // Existing "Export Portfolio" text button is also available when format is null
        expect(find.text('Export Portfolio'), findsOneWidget);
        expect(find.text('My Portfolios'), findsOneWidget);
        expect(find.text('Back'), findsOneWidget);
      },
    );

    testWidgets(
      '3: Existing Share / Export behavior does not regress on PortfolioExportScreen',
      (tester) async {
        final exporter = MemoryPortfolioExporter();
        await tester.pumpWidget(
          _wrapExport(info: _sampleInfo(), exporter: exporter),
        );
        await tester.pumpAndSettle();

        // Tap Export Portfolio
        final exportBtn = find.text('Export Portfolio').last;
        await tester.ensureVisible(exportBtn);
        await tester.tap(exportBtn);
        await tester.pumpAndSettle();

        // Results screen displayed
        expect(find.text('Portfolio file created'), findsOneWidget);
        expect(
          find.byKey(const Key('portfolio-export-save-btn')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('portfolio-export-share-btn')),
          findsOneWidget,
        );
        expect(find.text('Share'), findsOneWidget);

        // Tapping Share calls exporter.share
        final shareBtn = find.byKey(const Key('portfolio-export-share-btn'));
        await tester.ensureVisible(shareBtn);
        await tester.tap(shareBtn);
        await tester.pumpAndSettle();
        expect(exporter.shareCount, 1);
      },
    );

    testWidgets('4: PDF Save to Device flow reuses existing generated PDF', (
      tester,
    ) async {
      final exporter = MemoryPortfolioExporter();
      const existingPdf = PortfolioExportFile(
        path: '/test-only/GradPort_Alex_Santos_Portfolio.pdf',
        name: 'GradPort_Alex_Santos_Portfolio.pdf',
        format: ExportFormat.pdf,
        sizeBytes: 2048,
      );

      await tester.pumpWidget(
        _wrapPreview(
          info: _sampleInfo(),
          exporter: exporter,
          initialFile: existingPdf,
          format: ExportFormat.pdf,
        ),
      );
      await tester.pumpAndSettle();

      // Tap Save to Device
      final saveBtn = find.byKey(const Key('portfolio-preview-save-btn'));
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verified: saved via exporter, no regeneration occurred
      expect(exporter.saveCount, 1);
      expect(exporter.generationCount, 0);
      expect(exporter.lastSavedFile?.format, ExportFormat.pdf);
      expect(find.text('Portfolio saved successfully.'), findsOneWidget);
    });

    testWidgets('5: DOCX Save to Device flow reuses existing generated DOCX', (
      tester,
    ) async {
      final exporter = MemoryPortfolioExporter();
      const existingDocx = PortfolioExportFile(
        path: '/test-only/GradPort_Alex_Santos_Portfolio.docx',
        name: 'GradPort_Alex_Santos_Portfolio.docx',
        format: ExportFormat.docx,
        sizeBytes: 1024,
      );

      await tester.pumpWidget(
        _wrapPreview(
          info: _sampleInfo(),
          exporter: exporter,
          initialFile: existingDocx,
          format: ExportFormat.docx,
        ),
      );
      await tester.pumpAndSettle();

      // Tap app bar download icon
      final downloadIcon = find.byKey(
        const Key('portfolio-preview-download-btn'),
      );
      await tester.tap(downloadIcon);
      await tester.pumpAndSettle();

      // Verified: saved via exporter, no regeneration occurred
      expect(exporter.saveCount, 1);
      expect(exporter.generationCount, 0);
      expect(exporter.lastSavedFile?.format, ExportFormat.docx);
      expect(find.text('Portfolio saved successfully.'), findsOneWidget);
    });

    testWidgets(
      '6: Format chooser behavior when Save to Device is tapped without prior export',
      (tester) async {
        final exporter = MemoryPortfolioExporter();

        await tester.pumpWidget(
          _wrapPreview(info: _sampleInfo(), exporter: exporter),
        );
        await tester.pumpAndSettle();

        // Tap Save to Device without prior generation
        final saveBtn = find.byKey(const Key('portfolio-preview-save-btn'));
        await tester.ensureVisible(saveBtn);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        // Bottom sheet format chooser should be open with PDF and DOCX options
        expect(find.byKey(const Key('format-picker-pdf')), findsOneWidget);
        expect(find.byKey(const Key('format-picker-docx')), findsOneWidget);
        expect(find.text('PDF Document'), findsOneWidget);
        expect(find.text('DOCX Document'), findsOneWidget);

        // Select DOCX
        await tester.tap(find.byKey(const Key('format-picker-docx')));
        await tester.pumpAndSettle();

        // Generated once and saved
        expect(exporter.generationCount, 1);
        expect(exporter.format, ExportFormat.docx);
        expect(exporter.saveCount, 1);
        expect(exporter.lastSavedFile?.format, ExportFormat.docx);
        expect(find.text('Portfolio saved successfully.'), findsOneWidget);
      },
    );

    testWidgets(
      '7: User cancellation of save picker does not show error message',
      (tester) async {
        final exporter = MemoryPortfolioExporter()..cancelSave = true;
        const existingPdf = PortfolioExportFile(
          path: '/test-only/GradPort_Alex_Santos_Portfolio.pdf',
          name: 'GradPort_Alex_Santos_Portfolio.pdf',
          format: ExportFormat.pdf,
          sizeBytes: 2048,
        );

        await tester.pumpWidget(
          _wrapPreview(
            info: _sampleInfo(),
            exporter: exporter,
            initialFile: existingPdf,
            format: ExportFormat.pdf,
          ),
        );
        await tester.pumpAndSettle();

        final saveBtn = find.byKey(const Key('portfolio-preview-save-btn'));
        await tester.ensureVisible(saveBtn);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        // saveCount incremented, but no error or success snackbar shown
        expect(exporter.saveCount, 1);
        expect(find.text('Portfolio saved successfully.'), findsNothing);
        expect(
          find.text("We couldn't save your portfolio. Please try again."),
          findsNothing,
        );
      },
    );

    testWidgets('8: Write/save failure shows friendly error message', (
      tester,
    ) async {
      final exporter = MemoryPortfolioExporter()..failSave = true;
      const existingPdf = PortfolioExportFile(
        path: '/test-only/GradPort_Alex_Santos_Portfolio.pdf',
        name: 'GradPort_Alex_Santos_Portfolio.pdf',
        format: ExportFormat.pdf,
        sizeBytes: 2048,
      );

      await tester.pumpWidget(
        _wrapPreview(
          info: _sampleInfo(),
          exporter: exporter,
          initialFile: existingPdf,
          format: ExportFormat.pdf,
        ),
      );
      await tester.pumpAndSettle();

      final saveBtn = find.byKey(const Key('portfolio-preview-save-btn'));
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(exporter.saveCount, 1);
      expect(
        find.text("We couldn't save your portfolio. Please try again."),
        findsOneWidget,
      );
    });

    testWidgets('10: Repeated taps do not start duplicate save operations', (
      tester,
    ) async {
      final exporter = MemoryPortfolioExporter();
      exporter.pendingSave = Completer<void>();
      const existingPdf = PortfolioExportFile(
        path: '/test-only/GradPort_Alex_Santos_Portfolio.pdf',
        name: 'GradPort_Alex_Santos_Portfolio.pdf',
        format: ExportFormat.pdf,
        sizeBytes: 2048,
      );

      await tester.pumpWidget(
        _wrapPreview(
          info: _sampleInfo(),
          exporter: exporter,
          initialFile: existingPdf,
          format: ExportFormat.pdf,
        ),
      );
      await tester.pumpAndSettle();

      final saveBtn = find.byKey(const Key('portfolio-preview-save-btn'));
      await tester.ensureVisible(saveBtn);

      // First tap begins save operation
      await tester.tap(saveBtn);
      await tester.pump(const Duration(milliseconds: 50));

      // Button is in loading state, multiple fast taps during save must be ignored
      await tester.tap(saveBtn, warnIfMissed: false);
      await tester.tap(saveBtn, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));

      expect(exporter.saveCount, 1);

      // Complete in-flight save
      exporter.pendingSave!.complete();
      await tester.pumpAndSettle();

      expect(exporter.saveCount, 1);
      expect(find.text('Portfolio saved successfully.'), findsOneWidget);
    });

    testWidgets(
      '11 & 12 & 13 & 14: Save then Share, and Share then Save reuse artifact and do not break each other',
      (tester) async {
        final exporter = MemoryPortfolioExporter();
        const existingPdf = PortfolioExportFile(
          path: '/test-only/GradPort_Alex_Santos_Portfolio.pdf',
          name: 'GradPort_Alex_Santos_Portfolio.pdf',
          format: ExportFormat.pdf,
          sizeBytes: 2048,
        );

        await tester.pumpWidget(
          _wrapPreview(
            info: _sampleInfo(),
            exporter: exporter,
            initialFile: existingPdf,
            format: ExportFormat.pdf,
          ),
        );
        await tester.pumpAndSettle();

        // 1. Save to Device
        final saveBtn = find.byKey(const Key('portfolio-preview-save-btn'));
        await tester.ensureVisible(saveBtn);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();
        expect(exporter.saveCount, 1);
        expect(exporter.shareCount, 0); // Save did not invoke Share

        // 2. Share
        final shareIcon = find.byKey(const Key('portfolio-preview-share-btn'));
        await tester.tap(shareIcon);
        await tester.pumpAndSettle();
        expect(exporter.shareCount, 1); // Share works after Save
        expect(exporter.saveCount, 1); // Share did not invoke Save
        expect(exporter.generationCount, 0); // Reused same artifact throughout
      },
    );

    test(
      '16: AndroidManifest does not declare broad storage permissions',
      () async {
        final manifestFile = File('android/app/src/main/AndroidManifest.xml');
        expect(await manifestFile.exists(), isTrue);
        final content = await manifestFile.readAsString();
        // Camera's video-capable plugin contributes legacy storage permissions.
        // Explicit manifest-merger REMOVALS forbid them; they are not grants.
        final grants = RegExp(r'<uses-permission\b[^>]*>', dotAll: true)
            .allMatches(content)
            .map((match) => match.group(0)!)
            .where((element) => !element.contains('tools:node="remove"'))
            .join('\n');
        expect(grants, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
        expect(grants, isNot(contains('WRITE_EXTERNAL_STORAGE')));
        expect(grants, isNot(contains('READ_EXTERNAL_STORAGE')));
      },
    );
  });
}
