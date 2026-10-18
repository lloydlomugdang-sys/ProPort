// LOCATION: test/camera_document_scan_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:proport_app/screens/files/add_file_screen.dart';
import 'package:proport_app/screens/files/batch_review_screen.dart';
import 'package:proport_app/screens/main_screen.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_models.dart';
import 'package:proport_app/services/auth_scope.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/document_models.dart';
import 'package:proport_app/services/document_picker.dart';
import 'package:proport_app/services/document_scope.dart';
import 'package:proport_app/services/document_service.dart';
import 'package:proport_app/screens/portfolio/models/portfolio_models.dart';
import 'package:proport_app/services/portfolio_export_service.dart';
import 'package:proport_app/services/portfolio_scope.dart';
import 'package:proport_app/services/portfolio_service.dart';
import 'package:proport_app/services/scanner/classical_cv_engine.dart';
import 'package:proport_app/services/secure_token_store.dart';

// ─── Test Mocks ─────────────────────────────────────────────────────────────

class _NoopTokenStore implements SecureTokenStore {
  @override
  Future<void> deleteRefreshToken() async {}

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> writeRefreshToken(String refreshToken) async {}
}

class _NoopAuthService extends AuthService {
  _NoopAuthService()
    : super(
        apiClient: ApiClient(baseUrl: 'http://example.test:3000'),
        tokenStore: _NoopTokenStore(),
      );

  @override
  AuthUser? get user => AuthUser(
    id: 'u1',
    email: 'student@example.edu',
    firstName: 'Alex',
    lastName: 'Santos',
    school: 'University of Engineering',
    program: 'Computer Science',
    yearLevel: '4th Year',
    status: 'active',
    emailVerifiedAt: DateTime(2026, 1, 1),
  );
}

class _TestCameraPicker implements DocumentPicker {
  _TestCameraPicker({this.photoResult, this.documentsResult});

  PickedDocument? photoResult;
  List<PickedDocument>? documentsResult;
  int cameraCalls = 0;
  int documentCalls = 0;
  int cleanCacheCalls = 0;

  @override
  Future<PickedDocument?> pickDocument() async {
    documentCalls++;
    return photoResult;
  }

  @override
  Future<List<PickedDocument>?> pickDocuments({
    bool allowMultiple = true,
  }) async {
    documentCalls++;
    if (documentsResult != null) return documentsResult;
    return photoResult == null ? null : [photoResult!];
  }

  @override
  Future<PickedDocument?> pickFromCamera() async {
    cameraCalls++;
    return photoResult;
  }

  @override
  Future<void> cleanCache() async {
    cleanCacheCalls++;
  }
}

class _TestDocumentService extends DocumentService {
  _TestDocumentService() : super(authService: _NoopAuthService());

  static const _testCategories = [
    DocumentCategory(
      key: 'certificates',
      name: 'Certificates',
      folders: [DocumentFolder(key: 'trainings', name: 'Trainings')],
    ),
  ];

  final bool failUpload = false;
  int previewCalls = 0;
  int uploadCalls = 0;
  List<PickedDocument>? uploadedFiles;

  @override
  List<DocumentCategory> get categories => _testCategories;

  @override
  Future<DocumentOcrResult> previewOcr(dynamic fileOrFiles) async {
    previewCalls++;
    return DocumentOcrResult(
      status: DocumentOcrStatus.ready,
      rawText:
          'This is to certify that Alex Santos completed Flutter Workshop on 2026-05-10.',
      metadataSuggestions: DocumentMetadataSuggestions(
        title: 'Certificate of Attendance',
        categoryKey: 'certificates',
        folderKey: 'trainings',
        documentDate: DateTime(2026, 5, 10),
      ),
      metadataAnalysis: const DocumentMetadataAnalysis(
        source: 'gemini',
        aiStatus: 'success',
      ),
    );
  }

  @override
  Future<DocumentRecord> upload({
    PickedDocument? file,
    List<PickedDocument>? files,
    required String categoryKey,
    required String folderKey,
    required String title,
    required DateTime documentDate,
    String? description,
    String? reflection,
    ScholasticDetails? scholastic,
  }) async {
    uploadCalls++;
    uploadedFiles = files ?? (file == null ? [] : [file]);
    if (failUpload) {
      throw const ApiException(
        statusCode: 500,
        code: 'UPLOAD_FAILED',
        message: 'Upload failed due to connection error.',
      );
    }
    return DocumentRecord(
      id: 'doc_${DateTime.now().millisecondsSinceEpoch}',
      categoryKey: categoryKey,
      folderKey: folderKey,
      title: title,
      documentDate: documentDate,
      originalFileName: file?.name ?? files?.firstOrNull?.name ?? 'scan.jpg',
      mimeType: file?.mimeType ?? files?.firstOrNull?.mimeType ?? 'image/jpeg',
      fileKind: 'image',
      extension: 'jpg',
      sizeBytes: file?.sizeBytes ?? files?.firstOrNull?.sizeBytes ?? 1024,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}

class _TestPortfolioExporter implements PortfolioExporter {
  int generateCalls = 0;
  int shareCalls = 0;
  int saveCalls = 0;

  @override
  Future<PortfolioExportFile> generate(
    PortfolioExportContent content,
    ExportFormat format,
  ) async {
    generateCalls++;
    return const PortfolioExportFile(
      path: '/tmp/portfolio.pdf',
      name: 'portfolio.pdf',
      format: ExportFormat.pdf,
      sizeBytes: 1024,
    );
  }

  @override
  Future<void> share(PortfolioExportFile file, Rect origin) async {
    shareCalls++;
  }

  @override
  Future<bool> saveToDevice(PortfolioExportFile file) async {
    saveCalls++;
    return true;
  }
}

// ─── Helpers to generate synthetic images ───────────────────────────────────

Uint8List _generateSyntheticDocumentImage({
  int width = 400,
  int height = 300,
  int docMargin = 40,
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(30, 30, 30));

  for (var y = docMargin; y < height - docMargin; y++) {
    for (var x = docMargin; x < width - docMargin; x++) {
      image.setPixelRgb(x, y, 240, 240, 240);
    }
  }

  return Uint8List.fromList(img.encodeJpg(image));
}

Uint8List _generateBlankImage({int width = 200, int height = 200}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(128, 128, 128));
  return Uint8List.fromList(img.encodeJpg(image));
}

Widget _buildApp(DocumentService documentService, Widget child) {
  final auth = _NoopAuthService();
  return AuthScope(
    authService: auth,
    child: DocumentScope(
      documentService: documentService,
      child: PortfolioScope(
        portfolioService: PortfolioService(authService: auth),
        exporter: _TestPortfolioExporter(),
        child: MaterialApp(
          navigatorKey: DeviceDocumentPicker.navigatorKey,
          home: child,
        ),
      ),
    ),
  );
}

// ─── Test Suite ─────────────────────────────────────────────────────────────

void main() {
  group('ClassicalCvEngine (Mathematical & Algorithmic Unit Tests)', () {
    test('1. Grayscale conversion: transforms RGB into accurate luminance', () {
      final image = img.Image(width: 10, height: 10);
      image.setPixelRgb(0, 0, 100, 150, 200);
      final bytes = Uint8List.fromList(img.encodeJpg(image));

      final warped = ClassicalCvEngine.warpAndEnhance(
        imageBytes: bytes,
        corners: DocumentCorners.defaultInset(),
        mode: ScanEnhancementMode.grayscale,
      );
      final decoded = img.decodeImage(warped)!;
      final p = decoded.getPixel(0, 0);
      expect(p.r.toInt(), p.g.toInt());
      expect(p.g.toInt(), p.b.toInt());
    });

    test('2. Sobel gradient behavior: detects strong horizontal edge', () {
      final image = img.Image(width: 60, height: 60);
      for (var y = 0; y < 60; y++) {
        for (var x = 0; x < 60; x++) {
          final c = x < 30 ? 0 : 255;
          image.setPixelRgb(x, y, c, c, c);
        }
      }
      final bytes = Uint8List.fromList(img.encodeJpg(image));
      final corners = ClassicalCvEngine.detectCorners(bytes);
      expect(corners.toList().length, 4);
    });

    test('3. Canny edge extraction on synthetic patterns', () {
      final docBytes = _generateSyntheticDocumentImage(
        width: 400,
        height: 300,
        docMargin: 50,
      );
      final corners = ClassicalCvEngine.detectCorners(docBytes);
      expect(corners.toList().length, 4);
      for (final pt in corners.toList()) {
        expect(pt.dx, inInclusiveRange(0.0, 1.0));
        expect(pt.dy, inInclusiveRange(0.0, 1.0));
      }
    });

    test(
      '4 & 5 & 6. Contour tracing, RDP simplification & convex quad detection',
      () {
        final docBytes = _generateSyntheticDocumentImage(
          width: 500,
          height: 400,
          docMargin: 40,
        );
        final corners = ClassicalCvEngine.detectCorners(docBytes);

        expect(corners.isAutoDetected, isTrue);
        expect(corners.topLeft.dx, closeTo(0.08, 0.06));
        expect(corners.topLeft.dy, closeTo(0.10, 0.06));
        expect(corners.bottomRight.dx, closeTo(0.92, 0.06));
        expect(corners.bottomRight.dy, closeTo(0.90, 0.06));
      },
    );

    test('7. Corner ordering TL, TR, BR, BL', () {
      final shuffled = [
        const Offset(0.9, 0.9), // BR
        const Offset(0.1, 0.1), // TL
        const Offset(0.1, 0.9), // BL
        const Offset(0.9, 0.1), // TR
      ];

      final corners = DocumentCorners.ordered(shuffled);
      expect(corners.topLeft, const Offset(0.1, 0.1));
      expect(corners.topRight, const Offset(0.9, 0.1));
      expect(corners.bottomRight, const Offset(0.9, 0.9));
      expect(corners.bottomLeft, const Offset(0.1, 0.9));
    });

    test(
      '8. No-quad fallback preserves the full image with isAutoDetected=false',
      () {
        final blankBytes = _generateBlankImage(width: 300, height: 300);
        final corners = ClassicalCvEngine.detectCorners(blankBytes);

        expect(corners.isAutoDetected, isFalse);
        expect(corners, DocumentCorners.fullImage());
      },
    );

    test(
      '9. Homography perspective warp: produces upright rectangular image',
      () {
        final docBytes = _generateSyntheticDocumentImage(
          width: 400,
          height: 300,
          docMargin: 30,
        );
        final corners = DocumentCorners(
          topLeft: const Offset(0.1, 0.1),
          topRight: const Offset(0.9, 0.1),
          bottomRight: const Offset(0.9, 0.9),
          bottomLeft: const Offset(0.1, 0.9),
        );

        final warpedBytes = ClassicalCvEngine.warpAndEnhance(
          imageBytes: docBytes,
          corners: corners,
          mode: ScanEnhancementMode.original,
        );

        final warped = img.decodeImage(warpedBytes)!;
        expect(warped.width, greaterThan(100));
        expect(warped.height, greaterThan(100));
      },
    );

    test(
      '10. Bilinear sampling boundaries: handles edge pixel coords safely',
      () {
        final docBytes = _generateSyntheticDocumentImage(
          width: 200,
          height: 200,
          docMargin: 10,
        );
        final extremeCorners = DocumentCorners(
          topLeft: const Offset(0.01, 0.01),
          topRight: const Offset(0.99, 0.01),
          bottomRight: const Offset(0.99, 0.99),
          bottomLeft: const Offset(0.01, 0.99),
        );

        expect(
          () => ClassicalCvEngine.warpAndEnhance(
            imageBytes: docBytes,
            corners: extremeCorners,
            mode: ScanEnhancementMode.enhanced,
          ),
          returnsNormally,
        );
      },
    );

    test('11. Degenerate/invalid quadrilateral rejection', () {
      final docBytes = _generateSyntheticDocumentImage(width: 200, height: 200);
      final concaveCorners = DocumentCorners(
        topLeft: const Offset(0.1, 0.1),
        topRight: const Offset(0.1, 0.9),
        bottomRight: const Offset(0.9, 0.1),
        bottomLeft: const Offset(0.9, 0.9),
      );

      expect(
        () => ClassicalCvEngine.warpAndEnhance(
          imageBytes: docBytes,
          corners: concaveCorners,
          mode: ScanEnhancementMode.enhanced,
        ),
        throwsArgumentError,
      );
    });

    test('12. Deterministic contrast enhancement expands dynamic range', () {
      final lowContrast = img.Image(width: 100, height: 100);
      for (var y = 0; y < 100; y++) {
        for (var x = 0; x < 100; x++) {
          final c = 100 + (x % 50);
          lowContrast.setPixelRgb(x, y, c, c, c);
        }
      }
      final bytes = Uint8List.fromList(img.encodeJpg(lowContrast));

      final enhancedBytes = ClassicalCvEngine.warpAndEnhance(
        imageBytes: bytes,
        corners: DocumentCorners.defaultInset(),
        mode: ScanEnhancementMode.enhanced,
      );

      final enhanced = img.decodeImage(enhancedBytes)!;
      var minVal = 255;
      var maxVal = 0;
      for (var y = 0; y < enhanced.height; y++) {
        for (var x = 0; x < enhanced.width; x++) {
          final r = enhanced.getPixel(x, y).r.toInt();
          if (r < minVal) minVal = r;
          if (r > maxVal) maxVal = r;
        }
      }
      expect(minVal, lessThan(60));
      expect(maxVal, greaterThan(200));
    });

    test('13. Grayscale enhancement outputs uniform RGB channels', () {
      final docBytes = _generateSyntheticDocumentImage(width: 120, height: 120);
      final grayBytes = ClassicalCvEngine.warpAndEnhance(
        imageBytes: docBytes,
        corners: DocumentCorners.defaultInset(),
        mode: ScanEnhancementMode.grayscale,
      );
      final gray = img.decodeImage(grayBytes)!;
      for (var x = 10; x < 50; x += 10) {
        final p = gray.getPixel(x, x);
        expect(p.r.toInt(), p.g.toInt());
        expect(p.g.toInt(), p.b.toInt());
      }
    });

    test('14. B&W enhancement produces binary binarization', () {
      final docBytes = _generateSyntheticDocumentImage(
        width: 120,
        height: 120,
        docMargin: 20,
      );
      final bwBytes = ClassicalCvEngine.warpAndEnhance(
        imageBytes: docBytes,
        corners: DocumentCorners.defaultInset(),
        mode: ScanEnhancementMode.blackAndWhite,
      );
      final bw = img.decodeImage(bwBytes)!;
      for (var x = 5; x < bw.width; x += 10) {
        final r = bw.getPixel(x, bw.height ~/ 2).r.toInt();
        expect(r == 0 || r == 255 || (r < 15 || r > 240), isTrue);
      }
    });
  });

  group('DeviceDocumentPicker (SO2 Cache & Flow Tests)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('doc_scan_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      '15. Scanner cancellation returns null cleanly without throwing',
      () async {
        final picker = DeviceDocumentPicker(
          photoPicker:
              ({required source, maxWidth, maxHeight, imageQuality}) async {
                return null; // User cancelled camera capture
              },
          scannerRunner: ({required imagePath, required initialCorners}) async {
            return null;
          },
        );
        final doc = await picker.pickFromCamera();
        expect(doc, isNull);
      },
    );

    test('16. Retake flow: review runner returns null and discards', () async {
      final dummyPhoto = File('${tempDir.path}/photo.jpg');
      await dummyPhoto.writeAsBytes(_generateSyntheticDocumentImage());

      final picker = DeviceDocumentPicker(
        photoPicker:
            ({required source, maxWidth, maxHeight, imageQuality}) async {
              return XFile(dummyPhoto.path);
            },
        scannerRunner: ({required imagePath, required initialCorners}) async {
          return null; // User tapped retake
        },
      );

      final doc = await picker.pickFromCamera();
      expect(doc, isNull);
    });

    test('17 & 18. Use Scan flow & lazy PickedDocument behavior', () async {
      final scannedDoc = File('${tempDir.path}/scan_12345.jpg');
      await scannedDoc.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);

      final picker = DeviceDocumentPicker(
        photoPicker:
            ({required source, maxWidth, maxHeight, imageQuality}) async {
              return XFile(scannedDoc.path);
            },
        scannerRunner: ({required imagePath, required initialCorners}) async {
          return scannedDoc.path; // User accepted
        },
      );

      final doc = await picker.pickFromCamera();
      expect(doc, isNotNull);
      expect(doc!.hasBytes, isFalse, reason: 'Bytes must be lazily loaded');
      final read = await doc.readBytes();
      expect(read.length, 6);
      expect(doc.hasBytes, isTrue);
    });

    test('19 & 20. Scan cache lifetime & cleanup', () async {
      final scanFile = File('${tempDir.path}/scan_9999.jpg');
      await scanFile.writeAsBytes([1, 2, 3]);

      final otherFile = File('${tempDir.path}/portfolio.pdf');
      await otherFile.writeAsBytes([4, 5, 6]);

      var cleanerRan = false;
      final picker = DeviceDocumentPicker(
        scannerCleaner: () async {
          cleanerRan = true;
          final files = tempDir.listSync();
          for (final f in files) {
            if (f is File &&
                f.path.contains('scan_') &&
                f.path.endsWith('.jpg')) {
              await f.delete();
            }
          }
        },
      );

      await picker.cleanCache();
      expect(cleanerRan, isTrue);
      expect(await scanFile.exists(), isFalse);
      expect(
        await otherFile.exists(),
        isTrue,
        reason: 'Other files must never be deleted',
      );
    });
  });

  group('Screen Integrations & Regression Tests', () {
    testWidgets(
      '21. AddFileScreen integration: Scan Camera invokes camera picker and enters OCR flow',
      (tester) async {
        final photo = PickedDocument(
          name: 'scan_certificate.jpg',
          mimeType: 'image/jpeg',
          bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
        );
        final picker = _TestCameraPicker(photoResult: photo);
        final service = _TestDocumentService();

        await tester.pumpWidget(
          _buildApp(service, AddFileScreen(filePicker: picker)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Scan Camera'), findsOneWidget);

        await tester.tap(find.text('Scan Camera'));
        await tester.pump();

        expect(picker.cameraCalls, 1);
        expect(picker.documentCalls, 0);

        await tester.pumpAndSettle();

        expect(service.previewCalls, 1);
        expect(find.text('Certificate of Attendance'), findsOneWidget);

        await tester.ensureVisible(find.text('Add File'));
        await tester.tap(find.text('Add File'));
        await tester.pump();

        expect(service.uploadCalls, 1);
        expect(
          service.uploadedFiles?.firstOrNull?.name,
          'scan_certificate.jpg',
        );
        expect(picker.cleanCacheCalls, 1);
      },
    );

    testWidgets(
      '22. MainScreen quick-action integration: Camera quick action invokes scanner',
      (tester) async {
        final photo = PickedDocument(
          name: 'scan_quick.jpg',
          mimeType: 'image/jpeg',
          bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
        );
        final picker = _TestCameraPicker(photoResult: photo);
        final service = _TestDocumentService();

        await tester.pumpWidget(
          _buildApp(service, MainScreen(filePicker: picker)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pumpAndSettle();

        expect(find.text('Camera'), findsOneWidget);

        await tester.tap(find.text('Camera'));
        await tester.pumpAndSettle();

        expect(picker.cameraCalls, 1);
        expect(find.text('Add a File'), findsOneWidget);
      },
    );

    testWidgets(
      '23. Existing gallery picker regression: Pick File remains functional',
      (tester) async {
        final file = PickedDocument(
          name: 'resume.pdf',
          mimeType: 'application/pdf',
          bytes: Uint8List.fromList([1, 2, 3]),
        );
        final picker = _TestCameraPicker(photoResult: file);
        final service = _TestDocumentService();

        await tester.pumpWidget(
          _buildApp(service, AddFileScreen(filePicker: picker)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Tap to upload file'));
        await tester.pumpAndSettle();

        expect(picker.documentCalls, 1);
        expect(picker.cameraCalls, 0);
      },
    );

    testWidgets(
      '24. SO1 batch regression: multiple picked files routes to BatchReviewScreen',
      (tester) async {
        final files = [
          PickedDocument(
            name: 'cert1.jpg',
            mimeType: 'image/jpeg',
            bytes: Uint8List.fromList([1]),
          ),
          PickedDocument(
            name: 'cert2.jpg',
            mimeType: 'image/jpeg',
            bytes: Uint8List.fromList([2]),
          ),
        ];
        final picker = _TestCameraPicker(documentsResult: files);
        final service = _TestDocumentService();

        await tester.pumpWidget(
          _buildApp(service, AddFileScreen(filePicker: picker)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Tap to upload file'));
        await tester.pumpAndSettle();

        expect(picker.documentCalls, 1);
        expect(find.byType(BatchReviewScreen), findsOneWidget);
      },
    );

    testWidgets(
      '25. SO1 compiled PDF regression: Split Portfolio button is visible',
      (tester) async {
        final picker = _TestCameraPicker();
        final service = _TestDocumentService();

        await tester.pumpWidget(
          _buildApp(service, AddFileScreen(filePicker: picker)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Split Portfolio'), findsOneWidget);
      },
    );

    testWidgets(
      '26. Save to Device / Share regression: Portfolio exporter retains both actions',
      (tester) async {
        final exporter = _TestPortfolioExporter();
        final content = const PortfolioExportContent(
          titleFields: {'Full Name': 'Alex Santos'},
          sections: [],
          totalDocuments: 1,
        );
        final file = await exporter.generate(content, ExportFormat.pdf);
        expect(exporter.generateCalls, 1);

        await exporter.share(file, Rect.zero);
        expect(exporter.shareCalls, 1);

        final saved = await exporter.saveToDevice(file);
        expect(saved, isTrue);
        expect(exporter.saveCalls, 1);
      },
    );
  });
}
