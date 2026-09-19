import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/screens/files/add_file_screen.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/document_models.dart';
import 'package:proport_app/services/document_picker.dart';
import 'package:proport_app/services/document_scope.dart';
import 'package:proport_app/services/document_service.dart';
import 'package:proport_app/services/secure_token_store.dart';

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
}

class _TestCameraPicker implements DocumentPicker {
  _TestCameraPicker({this.photoResult});

  PickedDocument? photoResult;
  int cameraCalls = 0;
  int documentCalls = 0;

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
    return photoResult == null ? null : [photoResult!];
  }

  @override
  Future<PickedDocument?> pickFromCamera() async {
    cameraCalls++;
    return photoResult;
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

  @override
  List<DocumentCategory> get categories => _testCategories;

  int previewCalls = 0;
  int uploadCalls = 0;
  PickedDocument? uploadedFile;

  @override
  Future<void> load({bool force = false}) async {}

  @override
  Future<DocumentOcrResult> previewOcr(dynamic fileOrFiles) async {
    previewCalls++;
    return DocumentOcrResult(
      status: DocumentOcrStatus.ready,
      rawText: 'CERTIFICATE OF ATTENDANCE\nAwarded to Juan Dela Cruz',
      metadataSuggestions: DocumentMetadataSuggestions(
        categoryKey: 'certificates',
        folderKey: 'trainings',
        title: 'Certificate of Attendance',
        documentDate: DateTime(2026, 9, 17),
        confidence: 'high',
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
  }) async {
    uploadCalls++;
    uploadedFile = file ?? files?.first;
    return DocumentRecord(
      id: 'doc_cam_1',
      categoryKey: categoryKey,
      folderKey: folderKey,
      title: title,
      documentDate: documentDate,
      description: description,
      reflection: reflection,
      originalFileName: uploadedFile?.name ?? 'camera.jpg',
      mimeType: uploadedFile?.mimeType ?? 'image/jpeg',
      fileKind: 'image',
      extension: 'jpg',
      sizeBytes: uploadedFile?.sizeBytes ?? 1024,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}

Widget _buildApp(DocumentService service, Widget child) {
  return MaterialApp(
    home: DocumentScope(documentService: service, child: child),
  );
}

void main() {
  testWidgets(
    'tapping Scan Camera invokes camera picker and enters OCR/AI pipeline',
    (tester) async {
      final photo = PickedDocument(
        name: 'scan_doc.jpg',
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
      expect(find.text('Batch Upload'), findsNothing);

      // Tap Scan Camera
      await tester.tap(find.text('Scan Camera'));
      await tester.pump();

      expect(picker.cameraCalls, 1);
      expect(picker.documentCalls, 0);

      await tester.pumpAndSettle();

      // Verify preview was requested and suggested title applied
      expect(service.previewCalls, 1);
      expect(find.text('scan_doc.jpg'), findsOneWidget);
      expect(find.text('Certificate of Attendance'), findsOneWidget);

      // Fill date if needed and submit
      await tester.ensureVisible(find.text('Add File'));
      await tester.tap(find.text('Add File'));
      await tester.pump();

      // Wait for upload
      expect(service.uploadCalls, 1);
      expect(service.uploadedFile?.name, 'scan_doc.jpg');
      expect(service.uploadedFile?.mimeType, 'image/jpeg');
    },
  );

  testWidgets('rejects unsupported camera capture extension with snackbar', (
    tester,
  ) async {
    final unsupported = PickedDocument(
      name: 'scan.gif',
      mimeType: 'image/gif',
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    final picker = _TestCameraPicker(photoResult: unsupported);
    final service = _TestDocumentService();

    await tester.pumpWidget(
      _buildApp(service, AddFileScreen(filePicker: picker)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan Camera'));
    await tester.pump();

    expect(picker.cameraCalls, 1);
    expect(
      find.text('Please capture a JPG, JPEG, or PNG image.'),
      findsOneWidget,
    );
    expect(service.previewCalls, 0);
  });
}
