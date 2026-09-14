import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proport_app/screens/home/home_screen.dart';
import 'package:proport_app/screens/files/files_screen.dart';
import 'package:proport_app/screens/files/view_files_screen.dart';
import 'package:proport_app/screens/portfolio/portfolio_list_screen.dart';
import 'package:proport_app/services/portfolio_scope.dart';
import 'package:proport_app/services/portfolio_service.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_models.dart';
import 'package:proport_app/services/auth_scope.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/document_models.dart';
import 'package:proport_app/services/document_scope.dart';
import 'package:proport_app/services/document_service.dart';
import 'package:proport_app/services/secure_token_store.dart';

void main() {
  const categoryLabels = {
    'Curriculum Vitae': 'curriculum-vitae',
    'Scholastic Record': 'scholastic-record',
    'Certificates': 'certificates',
    'Accomplishments': 'accomplishments',
    'Other Achievements': 'other-achievements',
    'College Report': 'college-report',
  };
  for (final category in categoryLabels.entries) {
    testWidgets(
      '${category.key} opens existing Files with correct empty category and Back returns Home',
      (tester) async {
        final auth = _DashboardAuthService(_user());
        final documents = _DashboardDocumentService(auth);
        addTearDown(() {
          documents.dispose();
          auth.dispose();
        });
        await tester.pumpWidget(_testApp(auth, documents));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Back'), findsNothing);
        await tester.ensureVisible(find.text(category.key));
        await tester.tap(find.text(category.key));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilesScreen>(find.byType(FilesScreen))
              .initialCategoryKey,
          category.value,
        );
        expect(
          tester
              .widget<ViewFilesScreen>(find.byType(ViewFilesScreen))
              .categoryKey,
          category.value,
        );
        expect(find.text('No files found.'), findsOneWidget);
        expect(find.byTooltip('Back'), findsOneWidget);
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );
  }
  testWidgets(
    'Dashboard category filter shows matching documents across folders only',
    (tester) async {
      final auth = _DashboardAuthService(_user());
      final documents = _DashboardDocumentService(
        auth,
        records: [
          _document('certificate-one.pdf', 'certificates', 'awards'),
          _document('certificate-two.pdf', 'certificates', 'seminars'),
          _document('private-other-category.pdf', 'curriculum-vitae', 'cv'),
        ],
      );
      addTearDown(() {
        documents.dispose();
        auth.dispose();
      });
      await tester.pumpWidget(_testApp(auth, documents));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Certificates'));
      await tester.tap(find.text('Certificates'));
      await tester.pumpAndSettle();
      expect(find.text('certificate-one.pdf'), findsOneWidget);
      expect(find.text('certificate-two.pdf'), findsOneWidget);
      expect(find.text('private-other-category.pdf'), findsNothing);
    },
  );
  testWidgets(
    'Generate starts at Title Page while My Portfolios opens history',
    (tester) async {
      final auth = _DashboardAuthService(_user());
      final documents = _DashboardDocumentService(auth);
      final portfolios = PortfolioService(authService: auth);
      addTearDown(() {
        portfolios.dispose();
        documents.dispose();
        auth.dispose();
      });
      await tester.pumpWidget(
        PortfolioScope(
          portfolioService: portfolios,
          child: _testApp(auth, documents),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Generate Portfolio'));
      await tester.tap(find.text('Generate Portfolio'));
      await tester.pumpAndSettle();
      expect(find.text('Title Page'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(find.byType(PortfolioListScreen), findsNothing);
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('My Portfolios'));
      await tester.tap(find.text('My Portfolios'));
      await tester.pumpAndSettle();
      expect(find.byType(PortfolioListScreen), findsOneWidget);
      expect(find.text('No portfolios yet.'), findsOneWidget);
    },
  );

  testWidgets('shows the authenticated user name, program, and year level', (
    tester,
  ) async {
    final auth = _DashboardAuthService(
      _user(
        firstName: 'Maria',
        lastName: 'Santos',
        program: 'Bachelor of Science in Computer Science',
        yearLevel: '4th Year',
      ),
    );

    final documents = _DashboardDocumentService(auth);
    await tester.pumpWidget(_testApp(auth, documents));
    await tester.pumpAndSettle();

    expect(find.text('Maria Santos'), findsOneWidget);
    expect(
      find.text('Bachelor of Science in Computer Science'),
      findsOneWidget,
    );
    expect(find.text('4th Year'), findsOneWidget);
    expect(find.text('John Dela Cruz'), findsNothing);
    expect(find.text('BS Information Technology'), findsNothing);
    expect(find.text('3rd year'), findsNothing);
    documents.dispose();
    auth.dispose();
  });

  testWidgets(
    'updates immediately when the shared authenticated user changes',
    (tester) async {
      final auth = _DashboardAuthService(
        _user(
          firstName: 'Before',
          lastName: 'Edit',
          program: 'Old Program',
          yearLevel: '2nd Year',
        ),
      );

      final documents = _DashboardDocumentService(auth);
      await tester.pumpWidget(_testApp(auth, documents));
      await tester.pumpAndSettle();
      expect(find.text('Before Edit'), findsOneWidget);

      auth.replaceUser(
        _user(
          firstName: 'After',
          lastName: 'Save',
          program: 'Updated Program',
          yearLevel: '3rd Year',
        ),
      );
      await tester.pump();

      expect(find.text('Before Edit'), findsNothing);
      expect(find.text('After Save'), findsOneWidget);
      expect(find.text('Updated Program'), findsOneWidget);
      expect(find.text('3rd Year'), findsOneWidget);
      documents.dispose();
      auth.dispose();
    },
  );

  testWidgets('shows neutral placeholders for missing optional values', (
    tester,
  ) async {
    final auth = _DashboardAuthService(
      _user(program: '', yearLevel: '', school: ''),
    );

    final documents = _DashboardDocumentService(auth);
    await tester.pumpWidget(_testApp(auth, documents));
    await tester.pumpAndSettle();

    expect(find.text('Program not set'), findsOneWidget);
    expect(find.text('Year level not set'), findsOneWidget);
    expect(find.text('School not set'), findsOneWidget);
    expect(find.text('BS Information Technology'), findsNothing);
    expect(find.text('3rd year'), findsNothing);
    documents.dispose();
    auth.dispose();
  });

  testWidgets('shows a lightweight loading state without fake user data', (
    tester,
  ) async {
    final auth = _DashboardAuthService(null);

    final documents = _DashboardDocumentService(auth);
    await tester.pumpWidget(_testApp(auth, documents));
    await tester.pump();

    expect(find.text('Loading profile...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('John Dela Cruz'), findsNothing);
    expect(find.text('BS Information Technology'), findsNothing);
    expect(find.text('3rd year'), findsNothing);
    documents.dispose();
    auth.dispose();
  });

  testWidgets(
    'shows real document totals and category-derived tracker states',
    (tester) async {
      final auth = _DashboardAuthService(_user());
      final documents = _DashboardDocumentService(
        auth,
        summary: const DocumentSummary(
          totalCount: 7,
          categoryCounts: {
            'curriculum-vitae': 1,
            'certificates': 2,
            'accomplishments': 3,
            'other-achievements': 1,
          },
          folderCounts: {
            'curriculum-vitae/creative-title': 1,
            'certificates/creative-title': 1,
          },
        ),
      );

      await tester.pumpWidget(_testApp(auth, documents));
      await tester.pumpAndSettle();

      expect(find.text('43'), findsNothing);
      expect(find.text('30'), findsNothing);
      expect(find.text('11'), findsNothing);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('2'), findsNWidgets(2));
      expect(find.text('3'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Incomplete'), findsOneWidget);
      expect(find.text('Complete'), findsNothing);

      documents.dispose();
      auth.dispose();
    },
  );

  testWidgets('updates Dashboard document counts from the shared state', (
    tester,
  ) async {
    final auth = _DashboardAuthService(_user());
    final documents = _DashboardDocumentService(auth);
    await tester.pumpWidget(_testApp(auth, documents));
    await tester.pumpAndSettle();
    expect(find.text('0'), findsNWidgets(5));

    documents.replaceSummary(
      const DocumentSummary(
        totalCount: 1,
        categoryCounts: {'certificates': 1},
        folderCounts: {'certificates/seminars': 1},
      ),
    );
    await tester.pump();

    expect(find.text('1'), findsNWidgets(2));
    expect(find.text('43'), findsNothing);
    documents.dispose();
    auth.dispose();
  });

  testWidgets('shows document loading without fake counts', (tester) async {
    final auth = _DashboardAuthService(_user());
    final documents = _DashboardDocumentService(auth, hasLoaded: false);

    await tester.pumpWidget(_testApp(auth, documents));
    await tester.pump();

    expect(find.text('Loading your documents...'), findsOneWidget);
    expect(find.text('43'), findsNothing);
    expect(find.text('11'), findsNothing);
    expect(find.text('30'), findsNothing);
    documents.dispose();
    auth.dispose();
  });
}

Widget _testApp(AuthService auth, DocumentService documents) {
  return AuthScope(
    authService: auth,
    child: DocumentScope(
      documentService: documents,
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
}

class _DashboardAuthService extends AuthService {
  _DashboardAuthService(this._currentUser)
    : super(
        apiClient: ApiClient(
          baseUrl: 'http://example.test:3000',
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'data': {},
                'meta': {'requestId': 'unused'},
              }),
              200,
            ),
          ),
        ),
        tokenStore: _NoopTokenStore(),
      );

  AuthUser? _currentUser;

  @override
  AuthUser? get user => _currentUser;

  @override
  Future<Map<String, dynamic>> authenticatedGetJson(String path) async {
    if (path == '/api/v1/portfolios') {
      return {
        'data': {'portfolios': <Object>[]},
        'meta': {'requestId': 'history'},
      };
    }
    return super.authenticatedGetJson(path);
  }

  void replaceUser(AuthUser user) {
    _currentUser = user;
    notifyListeners();
  }
}

class _NoopTokenStore implements SecureTokenStore {
  @override
  Future<void> deleteRefreshToken() async {}

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> writeRefreshToken(String refreshToken) async {}
}

class _DashboardDocumentService extends DocumentService {
  _DashboardDocumentService(
    AuthService auth, {
    DocumentSummary summary = DocumentSummary.empty,
    bool hasLoaded = true,
    this.records = const [],
  }) : _summary = summary,
       _hasLoaded = hasLoaded,
       super(authService: auth);

  DocumentSummary _summary;
  final List<DocumentRecord> records;
  @override
  List<DocumentRecord> get documents => records;
  final bool _hasLoaded;

  @override
  DocumentSummary get summary => _summary;

  @override
  bool get hasLoadedDocuments => _hasLoaded;

  @override
  bool get isLoading => !_hasLoaded;

  @override
  Future<void> load({bool force = false}) async {}

  void replaceSummary(DocumentSummary value) {
    _summary = value;
    notifyListeners();
  }
}

AuthUser _user({
  String firstName = 'Grad',
  String lastName = 'Student',
  String program = 'Information Technology',
  String yearLevel = '3rd Year',
  String school = 'New Era University',
}) {
  return AuthUser(
    id: 'user-1',
    email: 'student@example.com',
    firstName: firstName,
    lastName: lastName,
    program: program,
    yearLevel: yearLevel,
    school: school,
    status: 'active',
    emailVerifiedAt: DateTime.utc(2030),
  );
}

DocumentRecord _document(String name, String category, String folder) =>
    DocumentRecord(
      id: name,
      categoryKey: category,
      folderKey: folder,
      title: name,
      documentDate: DateTime.utc(2026),
      originalFileName: name,
      mimeType: 'application/pdf',
      fileKind: 'pdf',
      extension: 'pdf',
      sizeBytes: 10,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
