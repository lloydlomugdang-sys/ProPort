// LOCATION: lib/screens/auth/login_screen.dart

import 'package:flutter/material.dart';
import 'widgets/auth_form_scroll_view.dart';
import 'widgets/auth_form_feedback.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_client.dart';
import '../../services/auth_models.dart';
import '../../services/auth_scope.dart';
import '../../services/auth_service.dart';
import '../main_screen.dart';
import 'signup_screen.dart';
import 'forgot_password_screen.dart';
import 'verification_code_screen.dart';
import 'widgets/auth_text_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.initialMessage});

  final String? initialMessage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin, AuthFormFeedback<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;

  static const Color _bg = Color(0xFFDBE9EE);
  static const Color _cardColor = Color(0xFF166088);
  static const Color _btnColor = Color(0xFF7ECDF7);
  static const Color _btnText = Color(0xFF166088);
  static const Color _titleColor = Color(0xFF006677);

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fadeCtrl.forward();
      final message = widget.initialMessage;
      if (message != null) _showError(message);
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return email.length <= 320 &&
        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
  }

  Future<void> _loginUser() async {
    if (_isLoading || isRateLimited) return;
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty) {
      _showError('Please enter your email.');
      return;
    }
    if (!_isValidEmail(email)) {
      _showError('Please enter a valid email address.');
      return;
    }
    if (password.isEmpty) {
      _showError('Please enter your password.');
      return;
    }
    if (password.length > 128) {
      _showError('Password must be no more than 128 characters.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await AuthScope.of(context).login(email: email, password: password);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (_, __, ___) => const MainScreen(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
        (route) => false,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'EMAIL_NOT_VERIFIED') {
        Navigator.push(
          context,
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 320),
            pageBuilder: (_, __, ___) => VerificationCodeScreen(
              email: email,
              purpose: VerificationPurpose.emailVerification,
            ),
            transitionsBuilder: (_, anim, __, child) => FadeTransition(
              opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
              child: child,
            ),
          ),
        );
      } else {
        _showError(handleFormError(error));
      }
    } on AuthStorageException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Unable to log in right now. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.white),
          ),
          backgroundColor: _cardColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  void _onForgotPassword() {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, __, ___) => const ForgotPasswordScreen(),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: AuthFormScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Title ─────────────────────────────────────
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'Log ',
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: _titleColor,
                        ),
                      ),
                      TextSpan(
                        text: 'In',
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.w400,
                          color: _titleColor,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // ── Card ───────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildCard(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Email ──────────────────────────────────────────
          _fieldLabel('Email'),
          const SizedBox(height: 4),
          AuthTextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
          ),

          const SizedBox(height: 10),

          // ── Password ───────────────────────────────────────
          _fieldLabel('Password'),
          const SizedBox(height: 4),
          AuthTextField(
            controller: _passwordCtrl,
            obscureText: true,
            showVisibilityToggle: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _loginUser(),
            autofillHints: const [AutofillHints.password],
          ),

          const SizedBox(height: 12),

          // ── Login button ───────────────────────────────────
          _loginButton(),
          AuthRetryNotice(seconds: retrySeconds),

          const SizedBox(height: 8),

          // ── Forgot password ────────────────────────────────
          Center(
            child: GestureDetector(
              onTap: _onForgotPassword,
              child: Text(
                'Forgot password?',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // ── Don't have an account? Sign Up ─────────────────
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  "Don't have an account? ",
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    PageRouteBuilder(
                      transitionDuration: const Duration(milliseconds: 300),
                      pageBuilder: (_, __, ___) => const SignupScreen(),
                      transitionsBuilder: (_, anim, __, child) =>
                          FadeTransition(opacity: anim, child: child),
                    ),
                  ),
                  child: Text(
                    'Sign Up',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) => Text(
    text,
    style: GoogleFonts.poppins(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: Colors.white,
    ),
  );

  Widget _loginButton() {
    return GestureDetector(
      onTap: _isLoading || isRateLimited ? null : _loginUser,
      child: Container(
        width: double.infinity,
        height: 36,
        decoration: BoxDecoration(
          color: _btnColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_btnText),
                  ),
                )
              : Text(
                  'Login',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _btnText,
                  ),
                ),
        ),
      ),
    );
  }
}
