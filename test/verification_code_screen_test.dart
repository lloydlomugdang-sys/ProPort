import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proport_app/screens/auth/login_screen.dart';
import 'package:proport_app/screens/auth/verification_code_screen.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_models.dart';
import 'package:proport_app/services/auth_scope.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/secure_token_store.dart';

void main() {
  testWidgets('unverified login navigates without resending a code', (
    tester,
  ) async {
    final requestedPaths = <String>[];
    final api = ApiClient(
      baseUrl: 'http://example.test:3000',
      client: MockClient((request) async {
        requestedPaths.add(request.url.path);
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'EMAIL_NOT_VERIFIED',
              'message': 'Verify your email before signing in.',
              'requestId': 'request-login',
            },
          }),
          403,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final auth = AuthService(apiClient: api, tokenStore: _EmptyTokenStore());
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      AuthScope(
        authService: auth,
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'student@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'Password1');
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();

    expect(find.byType(VerificationCodeScreen), findsOneWidget);
    expect(requestedPaths, ['/api/v1/auth/login']);
  });

  testWidgets('shows six digits and resends only after an explicit tap', (
    tester,
  ) async {
    final requestedPaths = <String>[];
    final api = ApiClient(
      baseUrl: 'http://example.test:3000',
      client: MockClient((request) async {
        requestedPaths.add(request.url.path);
        return http.Response(
          jsonEncode({
            'data': {'status': 'accepted'},
            'meta': {'requestId': 'request-resend'},
          }),
          202,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final auth = AuthService(apiClient: api, tokenStore: _EmptyTokenStore());
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      AuthScope(
        authService: auth,
        child: const MaterialApp(
          home: VerificationCodeScreen(
            email: 'student@example.com',
            purpose: VerificationPurpose.emailVerification,
          ),
        ),
      ),
    );

    expect(find.byType(TextFormField), findsNWidgets(6));
    expect(requestedPaths, isEmpty);

    await tester.pump(const Duration(seconds: 61));
    await tester.tap(find.text('Resend Code'));
    await tester.pump();
    await tester.pump();

    expect(requestedPaths, ['/api/v1/auth/email-verification/resend']);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _EmptyTokenStore implements SecureTokenStore {
  @override
  Future<void> deleteRefreshToken() async {}

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> writeRefreshToken(String refreshToken) async {}
}
