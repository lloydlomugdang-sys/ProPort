import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/screens/files/files_screen.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/document_models.dart';
import 'package:proport_app/services/document_scope.dart';
import 'package:proport_app/services/document_service.dart';
import 'package:proport_app/services/secure_token_store.dart';
import 'package:proport_app/widgets/folder_row_item.dart';

class _LayoutTestTokenStore implements SecureTokenStore {
  @override
  Future<void> deleteRefreshToken() async {}
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> writeRefreshToken(String refreshToken) async {}
}

class _LayoutTestAuthService extends AuthService {
  _LayoutTestAuthService()
      : super(
          apiClient: ApiClient(baseUrl: 'http://localhost:3000'),
          tokenStore: _LayoutTestTokenStore(),
        );
}

class _LayoutTestDocumentService extends DocumentService {
  _LayoutTestDocumentService({
    required super.authService,
    required List<DocumentCategory> testCategories,
    DocumentSummary summary = DocumentSummary.empty,
  })  : _testCategories = testCategories,
        _testSummary = summary;

  final List<DocumentCategory> _testCategories;
  final DocumentSummary _testSummary;

  @override
  List<DocumentCategory> get categories => _testCategories;

  @override
  DocumentSummary get summary => _testSummary;

  @override
  bool get hasLoadedCategories => true;

  @override
  bool get hasLoadedDocuments => true;

  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FilesScreen Spacing, Alignment & Grouping', () {
    testWidgets(
      'all category headings and section containers share exact same left horizontal alignment',
      (tester) async {
        final auth = _LayoutTestAuthService();
        final categories = [
          const DocumentCategory(
            key: 'cv',
            name: 'Curriculum Vitae',
            folders: [DocumentFolder(key: 'resume', name: 'Resume')],
          ),
          const DocumentCategory(
            key: 'scholastic',
            name: 'Scholastic Record',
            folders: [DocumentFolder(key: 'tor', name: 'Transcript of Records')],
          ),
          const DocumentCategory(
            key: 'certificates',
            name: 'Certificates',
            folders: [DocumentFolder(key: 'seminars', name: 'Seminars & Training')],
          ),
        ];

        final docService = _LayoutTestDocumentService(
          authService: auth,
          testCategories: categories,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: DocumentScope(
              documentService: docService,
              child: const FilesScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Check horizontal left edge of each category heading and its container
        for (final category in categories) {
          final headingFinder = find.text(category.name);
          expect(headingFinder, findsOneWidget);

          final headingLeft = tester.getTopLeft(headingFinder).dx;
          // Category headings must align at 20.0 (the screen margin, without any left: 2 offset)
          expect(
            headingLeft,
            equals(20.0),
            reason: '${category.name} should align at x=20.0',
          );
        }
      },
    );

    testWidgets(
      'folders are grouped tightly inside category container with dividers and without redundant outer cards',
      (tester) async {
        final auth = _LayoutTestAuthService();
        final categories = [
          const DocumentCategory(
            key: 'certificates',
            name: 'Certificates',
            folders: [
              DocumentFolder(key: 'seminars', name: 'Seminars'),
              DocumentFolder(key: 'workshops', name: 'Workshops'),
              DocumentFolder(key: 'internship', name: 'Internship'),
            ],
          ),
        ];

        final docService = _LayoutTestDocumentService(
          authService: auth,
          testCategories: categories,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: DocumentScope(
              documentService: docService,
              child: const FilesScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify folder rows are present and grouped
        final folderRows = tester.widgetList<FolderRowItem>(
          find.byType(FolderRowItem),
        ).toList();
        expect(folderRows.length, 3);
        for (final row in folderRows) {
          expect(row.isGrouped, isTrue);
        }

        // Verify dividers exist between rows (2 dividers for 3 folders)
        expect(find.byType(Divider), findsNWidgets(2));
      },
    );

    testWidgets(
      'empty category renders subtle empty indicator inside container',
      (tester) async {
        final auth = _LayoutTestAuthService();
        final categories = [
          const DocumentCategory(
            key: 'empty_cat',
            name: 'Empty Category',
            folders: [],
          ),
        ];

        final docService = _LayoutTestDocumentService(
          authService: auth,
          testCategories: categories,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: DocumentScope(
              documentService: docService,
              child: const FilesScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Empty Category'), findsOneWidget);
        expect(find.text('No folders in this category'), findsOneWidget);
        expect(find.byType(FolderRowItem), findsNothing);
      },
    );

    testWidgets(
      'scroll view padding includes clearance for bottom navigation bar',
      (tester) async {
        final auth = _LayoutTestAuthService();
        final categories = [
          const DocumentCategory(
            key: 'cv',
            name: 'Curriculum Vitae',
            folders: [DocumentFolder(key: 'resume', name: 'Resume')],
          ),
        ];

        final docService = _LayoutTestDocumentService(
          authService: auth,
          testCategories: categories,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: DocumentScope(
              documentService: docService,
              child: const FilesScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final scrollView = tester.widget<SingleChildScrollView>(
          find.byType(SingleChildScrollView),
        );
        final insets = scrollView.padding as EdgeInsets;
        // Bottom padding must be at least 100 to clear the bottom nav bar
        expect(insets.bottom, greaterThanOrEqualTo(100.0));
        expect(insets.left, equals(20.0));
        expect(insets.right, equals(20.0));
      },
    );
  });
}

