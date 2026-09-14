import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proport_app/screens/auth/login_screen.dart';
import 'package:proport_app/screens/auth/signup_screen.dart';
import 'package:proport_app/screens/auth/verification_code_screen.dart';
import 'package:proport_app/screens/auth/widgets/auth_form_feedback.dart';
import 'package:proport_app/screens/main_screen.dart';
import 'package:proport_app/screens/settings/change_password_screen.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_scope.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/document_scope.dart';
import 'package:proport_app/services/document_service.dart';
import 'package:proport_app/services/form_validation.dart';
import 'package:proport_app/services/secure_token_store.dart';

void main() {
  testWidgets('pushed signup has a visible Back button returning to Login', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(LoginScreen));
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SignupScreen()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
  });
  test('personal names support Unicode and reject numeric characters', () {
    for (final name in [
      'John Lloyd',
      'Dela-Cruz',
      "O'Connor",
      'José',
      '李明',
      'O’Connor',
    ]) {
      expect(personalNameError(name), isNull);
    }
    for (final name in ['John123', 'Lomugdang9', 'Name١', 'Name９']) {
      expect(personalNameError(name), 'Names cannot contain numbers.');
    }
  });

  test('safe form mapping never exposes raw server details', () {
    const codes = {
      'INVALID_CREDENTIALS': 'Incorrect email or password.',
      'EMAIL_ALREADY_REGISTERED': 'An account with this email already exists.',
      'NETWORK_ERROR':
          'Unable to connect. Check your internet connection and try again.',
      'RATE_LIMITED': 'Too many attempts. Please wait a moment and try again.',
    };
    for (final entry in codes.entries) {
      expect(
        authFormError(
          ApiException(code: entry.key, message: 'internal-secret'),
        ),
        entry.value,
      );
    }
    for (final status in [400, 401, 403, 409, 429, 500, 503]) {
      expect(
        authFormError(
          ApiException(
            code: 'UNKNOWN',
            message: 'internal-secret',
            statusCode: status,
            fields: const {'unknown': 'internal-secret'},
          ),
        ),
        isNot(contains('internal-secret')),
      );
    }
  });

  testWidgets(
    'signup → OTP → authenticated Dashboard, invalid code stays signed out, restart restores session',
    (tester) async {
      final paths = <String>[];
      final store = _Store();
      final api = ApiClient(
        baseUrl: 'http://example.test',
        client: MockClient((request) async {
          paths.add(request.url.path);
          final body = request.body.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(request.body) as Map<String, dynamic>;
          if (request.url.path.endsWith('/register')) {
            expect(body['password'], ' Password9 ');
            expect(body.containsKey('confirmPassword'), isFalse);
            return _response({
              'user': {..._user, 'status': 'pendingVerification'},
            }, status: 201);
          }
          if (request.url.path.endsWith('/email-verification/verify')) {
            expect(body['email'], 'student@example.test');
            if (body['code'] != '123456') {
              return _error('INVALID_OR_EXPIRED_CODE', 400);
            }
            return _response(_session);
          }
          if (request.url.path.endsWith('/refresh')) return _response(_session);
          if (request.url.path == '/api/v1/users/me') {
            return _response({'user': _user});
          }
          throw StateError('Unexpected test request');
        }),
      );
      final auth = AuthService(apiClient: api, tokenStore: store);
      final documents = _Documents(auth);
      addTearDown(() {
        documents.dispose();
        auth.dispose();
        api.close();
      });
      await tester.pumpWidget(
        AuthScope(
          authService: auth,
          child: DocumentScope(
            documentService: documents,
            child: const MaterialApp(home: SignupScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      for (final entry in [
        'John Lloyd',
        'Dela-Cruz',
        'student@example.test',
        ' Password9 ',
        ' Password9 ',
      ].asMap().entries) {
        await tester.enterText(fields.at(entry.key), entry.value);
      }
      await tester.ensureVisible(find.text('Sign Up'));
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();
      expect(find.byType(VerificationCodeScreen), findsOneWidget);
      expect(auth.isAuthenticated, isFalse);
      for (var index = 0; index < 6; index++) {
        await tester.enterText(find.byType(TextField).at(index), '0');
      }
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(auth.isAuthenticated, isFalse);
      expect(store.value, isNull);
      for (var index = 0; index < 6; index++) {
        await tester.enterText(
          find.byType(TextField).at(index),
          '${index + 1}',
        );
      }
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.byType(MainScreen), findsOneWidget);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(auth.isAuthenticated, isTrue);
      expect(store.value, 'refresh-test');
      expect(store.writes, ['refresh-test']);
      expect(
        paths.any(
          (path) => path.endsWith('/login') || path.endsWith('/resend'),
        ),
        isFalse,
      );
      expect(
        Navigator.of(tester.element(find.byType(MainScreen))).canPop(),
        isFalse,
      );
      expect(find.byTooltip('Back'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      final restored = AuthService(apiClient: api, tokenStore: store);
      expect(
        await restored.restoreSession(),
        SessionRestoreResult.authenticated,
      );
      restored.dispose();
    },
  );

  testWidgets(
    'login ignores duplicate IME submissions and honors Retry-After without losing input',
    (tester) async {
      final pending = Completer<http.Response>();
      var calls = 0;
      final api = ApiClient(
        baseUrl: 'http://example.test',
        client: MockClient((_) {
          calls++;
          return pending.future;
        }),
      );
      final auth = AuthService(apiClient: api, tokenStore: _Store());
      addTearDown(() {
        auth.dispose();
        api.close();
      });
      await tester.pumpWidget(
        AuthScope(
          authService: auth,
          child: const MaterialApp(home: LoginScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'student@example.test',
      );
      await tester.enterText(find.byType(TextField).last, 'Password9');
      final submit = tester
          .widget<TextField>(find.byType(TextField).last)
          .onSubmitted!;
      submit('Password9');
      submit('Password9');
      await tester.pump();
      expect(calls, 1);
      pending.complete(
        _error('RATE_LIMITED', 429, headers: {'retry-after': '2'}),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Too many attempts. Please wait a moment and try again.'),
        findsOneWidget,
      );
      expect(find.text('Try again in 2 seconds.'), findsOneWidget);
      submit('Password9');
      await tester.pump();
      expect(calls, 1);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        'Password9',
      );
      await tester.pump(const Duration(seconds: 3));
      submit('Password9');
      await tester.pump();
      expect(calls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final succeeds in [false, true]) {
    testWidgets(
      'Change Password backend ${succeeds ? 'success clears session' : 'failure never reports success'}',
      (tester) async {
        final store = _Store();
        var changeCalls = 0;
        final changeRequests = <http.Request>[];
        final api = ApiClient(
          baseUrl: 'http://example.test',
          client: MockClient((request) async {
            if (request.url.path.endsWith('/login')) return _response(_session);
            changeRequests.add(request);
            changeCalls++;
            return succeeds
                ? _response({'status': 'passwordChanged'})
                : _error('INTERNAL_ERROR', 500);
          }),
        );
        final auth = AuthService(apiClient: api, tokenStore: store);
        addTearDown(() {
          auth.dispose();
          api.close();
        });
        await auth.login(
          email: 'student@example.test',
          password: ' OldPassword9 ',
        );
        await tester.pumpWidget(
          AuthScope(
            authService: auth,
            child: const MaterialApp(home: ChangePasswordScreen()),
          ),
        );
        await tester.pumpAndSettle();
        for (final entry in [
          ' OldPassword9 ',
          ' NewPassword8 ',
          ' NewPassword8 ',
        ].asMap().entries) {
          await tester.enterText(
            find.byType(TextField).at(entry.key),
            entry.value,
          );
        }
        final submit = tester
            .widget<TextField>(find.byType(TextField).last)
            .onSubmitted!;
        submit('');
        submit('');
        await tester.pumpAndSettle();
        expect(changeCalls, 1);
        expect(changeRequests.single.url.path, '/api/v1/auth/password/change');
        expect(
          changeRequests.single.headers['authorization'],
          'Bearer access-test',
        );
        expect(jsonDecode(changeRequests.single.body), {
          'currentPassword': ' OldPassword9 ',
          'newPassword': ' NewPassword8 ',
        });
        expect(auth.isAuthenticated, !succeeds);
        if (succeeds) {
          expect(find.byType(LoginScreen), findsOneWidget);
          expect(store.value, isNull);
        } else {
          expect(find.byType(ChangePasswordScreen), findsOneWidget);
          expect(
            find.text('Something went wrong on the server. Please try again.'),
            findsOneWidget,
          );
          expect(store.value, 'refresh-test');
          expect(
            tester
                .widget<TextField>(find.byType(TextField).last)
                .controller!
                .text,
            ' NewPassword8 ',
          );
        }
      },
    );
  }
}

class _Documents extends DocumentService {
  _Documents(AuthService auth) : super(authService: auth);
  @override
  Future<void> load({bool force = false}) async {}
}

class _Store implements SecureTokenStore {
  String? value;
  final writes = <String>[];
  @override
  Future<void> deleteRefreshToken() async {
    value = null;
  }

  @override
  Future<String?> readRefreshToken() async => value;
  @override
  Future<void> writeRefreshToken(String token) async {
    value = token;
    writes.add(token);
  }
}

const _user = {
  'id': 'user-test',
  'email': 'student@example.test',
  'firstName': 'John Lloyd',
  'lastName': 'Dela-Cruz',
  'program': '',
  'yearLevel': '',
  'school': 'New Era University',
  'status': 'active',
  'emailVerifiedAt': '2030-01-01T00:00:00Z',
};
final _session = {
  'user': _user,
  'tokens': {
    'tokenType': 'Bearer',
    'accessToken': 'access-test',
    'refreshToken': 'refresh-test',
    'accessTokenExpiresAt': '2030-01-01T00:15:00Z',
    'refreshTokenExpiresAt': '2030-01-31T00:00:00Z',
  },
};
http.Response _response(Map<String, dynamic> data, {int status = 200}) =>
    http.Response(
      jsonEncode({
        'data': data,
        'meta': {'requestId': 'test'},
      }),
      status,
      headers: {'content-type': 'application/json'},
    );
http.Response _error(
  String code,
  int status, {
  Map<String, String> headers = const {},
}) => http.Response(
  jsonEncode({
    'error': {
      'code': code,
      'message': 'internal detail not for UI',
      'requestId': 'test',
    },
  }),
  status,
  headers: {'content-type': 'application/json', ...headers},
);
