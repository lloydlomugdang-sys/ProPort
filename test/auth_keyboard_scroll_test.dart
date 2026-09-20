import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/screens/auth/forgot_password_screen.dart';
import 'package:proport_app/screens/auth/login_screen.dart';
import 'package:proport_app/screens/auth/new_password_screen.dart';
import 'package:proport_app/screens/auth/signup_screen.dart';
import 'package:proport_app/screens/auth/verification_code_screen.dart';
import 'package:proport_app/services/auth_models.dart';
import 'package:proport_app/screens/settings/change_password_screen.dart';

void main() {
  final screens = <String, ({Widget screen, String action})>{
    'Login': (screen: const LoginScreen(), action: 'Log In'),
    'Change Password': (
      screen: const ChangePasswordScreen(),
      action: 'Save Password',
    ),
    'Sign Up': (screen: const SignupScreen(), action: 'Sign Up'),
    'Forgot Password': (screen: const ForgotPasswordScreen(), action: 'Send'),
    'Reset Password': (
      screen: const NewPasswordScreen(resetToken: 'test-only-memory-grant'),
      action: 'Save Password',
    ),
    'Email OTP': (
      screen: const VerificationCodeScreen(
        email: 'student@example.test',
        purpose: VerificationPurpose.emailVerification,
      ),
      action: 'Continue',
    ),
    'Reset OTP': (
      screen: const VerificationCodeScreen(
        email: 'student@example.test',
        purpose: VerificationPurpose.passwordReset,
      ),
      action: 'Continue',
    ),
  };

  for (final entry in screens.entries) {
    for (final keyboardHeight in [540.0, 640.0]) {
      testWidgets('${entry.key} scrolls above a $keyboardHeight keyboard', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(MaterialApp(home: entry.value.screen));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final field = find.byType(TextField).last;
        await tester.showKeyboard(field);
        tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final scrollView = find.byType(SingleChildScrollView);
        expect(scrollView, findsOneWidget);
        final scrollable = find.descendant(
          of: scrollView,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );
        final position = tester.state<ScrollableState>(scrollable).position;
        expect(position.maxScrollExtent, greaterThan(0));
        position.jumpTo(0);
        await tester.pump();

        // Real drag gestures, without dismissing the keyboard, reach the button.
        for (var i = 0; i < 10; i++) {
          await tester.drag(scrollView, const Offset(0, -120));
          await tester.pumpAndSettle();
          if (position.pixels >= position.maxScrollExtent) break;
        }
        expect(position.pixels, greaterThan(0));
        final action = find.text(entry.value.action).last;
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.getRect(action).bottom, lessThan(844 - keyboardHeight));
        expect(tester.testTextInput.isVisible, isTrue);
        expect(tester.takeException(), isNull);

        // Focused input remains reachable when swiping back down as well.
        final endOffset = position.pixels;
        await tester.drag(scrollView, const Offset(0, 120));
        await tester.pumpAndSettle();
        expect(position.pixels, lessThan(endOffset));
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        expect(field.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);

        final eyes = find.byTooltip('Show password');
        if (eyes.evaluate().isNotEmpty) {
          final eye = eyes.last;
          await tester.ensureVisible(eye);
          await tester.pumpAndSettle();
          expect(eye.hitTestable(), findsOneWidget);
          expect(tester.widget<TextField>(field).obscureText, isTrue);
          await tester.tap(eye);
          await tester.pump();
          expect(tester.widget<TextField>(field).obscureText, isFalse);
          expect(find.byTooltip('Hide password'), findsWidgets);
        }

        tester.view.viewInsets = const FakeViewPadding();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
