import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/screens/portfolio/models/portfolio_models.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/document_models.dart';
import 'package:proport_app/services/portfolio_export_service.dart';
import 'package:proport_app/services/secure_token_store.dart';

class _MockTokenStore implements SecureTokenStore {
  @override
  Future<void> deleteRefreshToken() async {}

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> writeRefreshToken(String refreshToken) async {}
}

class _MockAuthService extends AuthService {
  _MockAuthService({this.pdfBytes, this.throwApiError})
    : super(
        apiClient: ApiClient(baseUrl: 'http://localhost:3000'),
        tokenStore: _MockTokenStore(),
      );

  final Uint8List? pdfBytes;
  final ApiException? throwApiError;
  String? requestedPath;
  Map<String, dynamic>? requestedBody;

  @override
  Future<Uint8List> authenticatedPostBytes(
    String path, {
    required Map<String, dynamic> body,
    Duration? requestTimeout,
  }) async {
    requestedPath = path;
    requestedBody = body;
    if (throwApiError != null) throw throwApiError!;
    return pdfBytes ?? Uint8List.fromList('%PDF-Mock'.codeUnits);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Multi-page document models', () {
    test('parses attachments list and calculates correct pageCount', () {
      final json = {
        'id': 'doc-123',
        'categoryKey': 'certificates',
        'folderKey': 'seminars',
        'title': 'Multi Page Seminar Certificate',
        'documentDate': '2026-09-14T00:00:00.000Z',
        'originalFileName': 'cert_page_1.jpg',
        'mimeType': 'image/jpeg',
        'fileKind': 'image',
        'extension': 'jpg',
        'sizeBytes': 204800,
        'attachments': [
          {
            'id': 'att-1',
            'order': 0,
            'originalFileName': 'cert_page_1.jpg',
            'mimeType': 'image/jpeg',
            'fileKind': 'image',
            'extension': 'jpg',
            'sizeBytes': 102400,
          },
          {
            'id': 'att-2',
            'order': 1,
            'originalFileName': 'cert_page_2.jpg',
            'mimeType': 'image/jpeg',
            'fileKind': 'image',
            'extension': 'jpg',
            'sizeBytes': 102400,
          },
        ],
        'createdAt': '2026-09-14T00:00:00.000Z',
        'updatedAt': '2026-09-14T00:00:00.000Z',
      };

      final doc = DocumentRecord.fromJson(json);
      expect(doc.id, 'doc-123');
      expect(doc.attachments, isNotNull);
      expect(doc.attachments!.length, 2);
      expect(doc.pageCount, 2);
      expect(doc.effectiveAttachments.length, 2);
      expect(doc.effectiveAttachments[0].order, 0);
      expect(doc.effectiveAttachments[0].originalFileName, 'cert_page_1.jpg');
      expect(doc.effectiveAttachments[1].order, 1);
      expect(doc.effectiveAttachments[1].originalFileName, 'cert_page_2.jpg');
    });

    test(
      'backward compatible with legacy single-file record without attachments',
      () {
        final legacyJson = {
          'id': 'doc-legacy',
          'categoryKey': 'scholastic-record',
          'folderKey': 'grades',
          'title': 'Transcript of Records',
          'documentDate': '2026-09-10T00:00:00.000Z',
          'originalFileName': 'transcript.pdf',
          'mimeType': 'application/pdf',
          'fileKind': 'pdf',
          'extension': 'pdf',
          'sizeBytes': 512000,
          'createdAt': '2026-09-10T00:00:00.000Z',
          'updatedAt': '2026-09-10T00:00:00.000Z',
        };

        final doc = DocumentRecord.fromJson(legacyJson);
        expect(doc.id, 'doc-legacy');
        expect(doc.attachments, isNull);
        expect(doc.pageCount, 1);
        expect(doc.effectiveAttachments.length, 1);
        expect(doc.effectiveAttachments.first.id, '1');
        expect(doc.effectiveAttachments.first.order, 0);
        expect(
          doc.effectiveAttachments.first.originalFileName,
          'transcript.pdf',
        );
      },
    );
  });

  group('DevicePortfolioExporter backend delegation', () {
    test(
      'delegates PDF export to backend when authService is provided',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'gradport_export_test_',
        );
        addTearDown(() async => root.delete(recursive: true));
        final store = PortfolioExportStore(
          temporaryDirectory: () async => root,
        );

        final mockPdfBytes = Uint8List.fromList(
          '%PDF-1.4 Mock Canonical Generated PDF'.codeUnits,
        );
        final mockAuth = _MockAuthService(pdfBytes: mockPdfBytes);
        final exporter = DevicePortfolioExporter(
          store: store,
          authService: mockAuth,
        );

        final content = PortfolioExportContent(
          titleFields: {
            'Full Name': 'Lloyd Lomugdang',
            'Year & Section': '4BSIT-1',
            'Schedule': 'MWF 9:00 AM',
            "Instructor's Name": 'Prof. Santos',
            'Course': 'BSIT',
            'Course Code': 'IT401',
            'Semester & Academic Year': '1st Sem 2026-2027',
          },
          totalDocuments: 3,
          sections: const [],
        );

        final file = await exporter.generate(content, ExportFormat.pdf);
        expect(file.format, ExportFormat.pdf);
        expect(file.name, contains('Lloyd_Lomugdang'));
        expect(mockAuth.requestedPath, '/api/v1/portfolios/export/pdf');
        expect(mockAuth.requestedBody?['fullName'], 'Lloyd Lomugdang');
        expect(mockAuth.requestedBody?['courseCode'], 'IT401');
      },
    );

    test(
      'maps backend PORTFOLIO_TOO_LARGE ApiException to PortfolioExportException',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'gradport_export_test_',
        );
        addTearDown(() async => root.delete(recursive: true));
        final store = PortfolioExportStore(
          temporaryDirectory: () async => root,
        );

        final mockAuth = _MockAuthService(
          throwApiError: const ApiException(
            code: 'PORTFOLIO_TOO_LARGE',
            message:
                'Total uncompressed size of portfolio artifacts exceeds 50MB limit.',
            statusCode: 400,
          ),
        );
        final exporter = DevicePortfolioExporter(
          store: store,
          authService: mockAuth,
        );

        final content = PortfolioExportContent(
          titleFields: {'Full Name': 'Student'},
          totalDocuments: 10,
          sections: const [],
        );

        expect(
          () => exporter.generate(content, ExportFormat.pdf),
          throwsA(
            isA<PortfolioExportException>().having(
              (e) => e.message,
              'message',
              contains('50MB limit'),
            ),
          ),
        );
      },
    );

    test(
      'throws honest connection error if offline or network error occurs',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'gradport_export_test_',
        );
        addTearDown(() async => root.delete(recursive: true));
        final store = PortfolioExportStore(
          temporaryDirectory: () async => root,
        );

        final mockAuth = _MockAuthService(
          throwApiError: const ApiException(
            code: 'NETWORK_ERROR',
            message:
                'Unable to reach the server. Check your connection and try again.',
            statusCode: 0,
          ),
        );
        final exporter = DevicePortfolioExporter(
          store: store,
          authService: mockAuth,
        );

        final content = PortfolioExportContent(
          titleFields: {'Full Name': 'Student'},
          totalDocuments: 1,
          sections: const [],
        );

        expect(
          () => exporter.generate(content, ExportFormat.pdf),
          throwsA(
            isA<PortfolioExportException>().having(
              (e) => e.message,
              'message',
              'Unable to generate your complete portfolio. Check your connection and try again.',
            ),
          ),
        );
      },
    );

    test(
      'throws honest connection error if authService is null (no local PDF fallback)',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'gradport_export_test_',
        );
        addTearDown(() async => root.delete(recursive: true));
        final store = PortfolioExportStore(
          temporaryDirectory: () async => root,
        );

        final exporter = DevicePortfolioExporter(
          store: store,
          authService: null,
        );

        final content = PortfolioExportContent(
          titleFields: {'Full Name': 'Student'},
          totalDocuments: 1,
          sections: const [],
        );

        expect(
          () => exporter.generate(content, ExportFormat.pdf),
          throwsA(
            isA<PortfolioExportException>().having(
              (e) => e.message,
              'message',
              'Unable to generate your complete portfolio. Check your connection and try again.',
            ),
          ),
        );
      },
    );
  });
}
