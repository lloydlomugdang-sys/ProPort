// LOCATION: test/widget_test.dart
// REPLACE the existing file entirely.
// FIX: old test referenced 'MyApp' which no longer exists — replaced with GradPortApp.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/main.dart';
import 'package:proport_app/screens/auth/login_screen.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/secure_token_store.dart';

void main() {
  testWidgets('GradPort app launches and resolves an empty session', (
    tester,
  ) async {
    final authService = AuthService(tokenStore: _EmptyTokenStore());
    addTearDown(authService.dispose);

    await tester.pumpWidget(GradPortApp(authService: authService));
    expect(find.byType(MaterialApp), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
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
