import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proport_app/screens/home/home_screen.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_models.dart';
import 'package:proport_app/services/auth_scope.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/document_models.dart';
import 'package:proport_app/services/document_scope.dart';
import 'package:proport_app/services/document_service.dart';
import 'package:proport_app/services/secure_token_store.dart';

void main() {
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
    final auth = _DashboardAuthService(_user(program: '', yearLevel: ''));

    final documents = _DashboardDocumentService(auth);
    await tester.pumpWidget(_testApp(auth, documents));
    await tester.pumpAndSettle();

    expect(find.text('Program not provided'), findsOneWidget);
    expect(find.text('Year level not provided'), findsOneWidget);
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
  }) : _summary = summary,
       _hasLoaded = hasLoaded,
       super(authService: auth);

  DocumentSummary _summary;
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
}) {
  return AuthUser(
    id: 'user-1',
    email: 'student@example.com',
    firstName: firstName,
    lastName: lastName,
    program: program,
    yearLevel: yearLevel,
    school: 'New Era University',
    status: 'active',
    emailVerifiedAt: DateTime.utc(2030),
  );
}
