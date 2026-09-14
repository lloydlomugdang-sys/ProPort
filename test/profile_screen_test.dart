import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proport_app/screens/profile/profile_screen.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_models.dart';
import 'package:proport_app/services/auth_scope.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/secure_token_store.dart';

void main() {
  testWidgets(
    'empty profile fields use display-only fallbacks replaced after save',
    (tester) async {
      final auth = _FakeAuthService(
        user: _user(program: '  ', yearLevel: '', school: '\t'),
      );
      await tester.pumpWidget(_testApp(auth));
      await tester.pumpAndSettle();
      expect(find.text('Program not set'), findsOneWidget);
      expect(find.text('Year level not set'), findsOneWidget);
      expect(find.text('School not set'), findsOneWidget);
      expect(find.text('student@example.com'), findsOneWidget);

      await tester.tap(find.byTooltip('Edit profile'));
      await tester.pumpAndSettle();
      // Display fallbacks never become the editable model or request values.
      expect(find.text('Program not set'), findsNothing);
      expect(auth.user.program, '  ');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await auth.updateCurrentUserProfile(
        firstName: 'Grad',
        lastName: 'Student',
        program: 'Information Technology',
        yearLevel: '4th Year',
        school: 'GradPort University',
      );
      await tester.pumpAndSettle();
      expect(find.text('Program not set'), findsNothing);
      expect(find.text('Year level not set'), findsNothing);
      expect(find.text('School not set'), findsNothing);
      expect(find.text('Information Technology'), findsOneWidget);
      expect(find.text('4th Year'), findsOneWidget);
      expect(find.text('GradPort University'), findsOneWidget);
      expect(auth.lastUpdate!.values, isNot(contains('Program not set')));
      auth.dispose();
    },
  );

  testWidgets('shows loading and then displays the fetched profile', (
    tester,
  ) async {
    final pending = Completer<AuthUser>();
    final auth = _FakeAuthService(user: _user(), pendingFetch: pending);

    await tester.pumpWidget(_testApp(auth));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.complete(
      _user(
        firstName: 'Mongo',
        lastName: 'Student',
        program: 'Computer Science',
        yearLevel: '4th Year',
        school: 'GradPort University',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mongo Student'), findsOneWidget);
    expect(find.text('student@example.com'), findsOneWidget);
    expect(find.text('Computer Science'), findsOneWidget);
    expect(find.text('4th Year'), findsOneWidget);
    expect(find.text('GradPort University'), findsOneWidget);
    expect(auth.fetchCalls, 1);
    auth.dispose();
  });

  testWidgets('shows a safe profile loading error with retry', (tester) async {
    final auth = _FakeAuthService(
      user: _user(),
      fetchError: const ApiException(
        code: 'AUTH_UNAVAILABLE',
        message: 'Profile service is temporarily unavailable.',
        statusCode: 503,
      ),
    );

    await tester.pumpWidget(_testApp(auth));
    await tester.pumpAndSettle();

    expect(
      find.text('Profile service is temporarily unavailable.'),
      findsOneWidget,
    );
    expect(find.text('Try Again'), findsOneWidget);
    auth.dispose();
  });

  testWidgets('edits and saves supported profile fields', (tester) async {
    final auth = _FakeAuthService(user: _user(program: 'Old Program'));

    await tester.pumpWidget(_testApp(auth));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit profile'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Old Program'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'New Program');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(auth.lastUpdate, {
      'firstName': 'Grad',
      'lastName': 'Student',
      'program': 'New Program',
      'yearLevel': '3rd Year',
      'school': 'New Era University',
    });
    expect(find.text('Profile updated successfully.'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('New Program'), findsOneWidget);
    auth.dispose();
  });

  testWidgets('keeps the edit screen open for a validation API error', (
    tester,
  ) async {
    final auth = _FakeAuthService(
      user: _user(program: 'Old Program'),
      updateError: const ApiException(
        code: 'VALIDATION_ERROR',
        message: 'The request is invalid.',
        statusCode: 400,
        fields: {
          'program': ['must contain at most 200 characters'],
        },
      ),
    );

    await tester.pumpWidget(_testApp(auth));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Old Program'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Rejected Program');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Changes'));
    await tester.pump();

    expect(find.text('must contain at most 200 characters'), findsOneWidget);
    expect(find.byTooltip('Save profile'), findsOneWidget);
    auth.dispose();
  });

  testWidgets('turns an authentication failure into a session-safe message', (
    tester,
  ) async {
    final auth = _FakeAuthService(
      user: _user(),
      fetchError: const ApiException(
        code: 'UNAUTHORIZED',
        message: 'Authentication is required.',
        statusCode: 401,
      ),
    );

    await tester.pumpWidget(_testApp(auth));
    await tester.pumpAndSettle();

    expect(
      find.text('Your session has expired. Please log in again.'),
      findsOneWidget,
    );
    auth.dispose();
  });
}

Widget _testApp(AuthService auth) {
  return AuthScope(
    authService: auth,
    child: const MaterialApp(home: ProfileScreen()),
  );
}

class _FakeAuthService extends AuthService {
  _FakeAuthService({
    required AuthUser user,
    this.pendingFetch,
    this.fetchError,
    this.updateError,
  }) : _currentUser = user,
       super(
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

  AuthUser _currentUser;
  final Completer<AuthUser>? pendingFetch;
  final Object? fetchError;
  final Object? updateError;
  int fetchCalls = 0;
  Map<String, String>? lastUpdate;

  @override
  AuthUser get user => _currentUser;

  @override
  Future<AuthUser> fetchCurrentUser() async {
    fetchCalls++;
    final error = fetchError;
    if (error != null) throw error;
    _currentUser = pendingFetch == null
        ? _currentUser
        : await pendingFetch!.future;
    notifyListeners();
    return _currentUser;
  }

  @override
  Future<AuthUser> updateCurrentUserProfile({
    required String firstName,
    required String lastName,
    required String program,
    required String yearLevel,
    required String school,
  }) async {
    lastUpdate = {
      'firstName': firstName,
      'lastName': lastName,
      'program': program,
      'yearLevel': yearLevel,
      'school': school,
    };
    final error = updateError;
    if (error != null) throw error;
    _currentUser = _user(
      firstName: firstName,
      lastName: lastName,
      program: program,
      yearLevel: yearLevel,
      school: school,
    );
    notifyListeners();
    return _currentUser;
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
