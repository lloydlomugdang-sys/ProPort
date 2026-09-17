// LOCATION: lib/screens/auth/signup_screen.dart

import 'package:flutter/material.dart';
import 'widgets/auth_form_scroll_view.dart';
import 'widgets/auth_form_feedback.dart';
import '../../services/form_validation.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../constants/app_colors.dart';
import '../../services/api_client.dart';
import '../../services/auth_models.dart';
import '../../services/auth_scope.dart';
import 'verification_code_screen.dart';
import 'widgets/auth_text_field.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin, AuthFormFeedback<SignupScreen> {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
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
      if (mounted) _fadeCtrl.forward();
    });
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return email.length <= 320 &&
        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
  }

  bool _isStrongPassword(String password) {
    final hasUpper = RegExp(r'[A-Z]').hasMatch(password);
    final hasLower = RegExp(r'[a-z]').hasMatch(password);
    final hasDigit = RegExp(r'\d').hasMatch(password);
    return hasUpper && hasLower && hasDigit;
  }

  Future<void> _createAccount() async {
    if (_isLoading || isRateLimited) return;
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;

    final nameError =
        personalNameError(firstName, 'first name') ??
        personalNameError(lastName, 'last name');
    if (nameError != null) {
      _showError(nameError);
      return;
    }

    if (firstName.isEmpty) {
      _showError('Please enter your first name.');
      return;
    }
    if (firstName.length < 2) {
      _showError('First name must be at least 2 characters.');
      return;
    }
    if (firstName.length > 100) {
      _showError('First name must be no more than 100 characters.');
      return;
    }
    if (lastName.isEmpty) {
      _showError('Please enter your last name.');
      return;
    }
    if (lastName.length < 2) {
      _showError('Last name must be at least 2 characters.');
      return;
    }
    if (lastName.length > 100) {
      _showError('Last name must be no more than 100 characters.');
      return;
    }
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
    if (password.length < 8) {
      _showError('Password must be at least 8 characters.');
      return;
    }
    if (password.length > 128) {
      _showError('Password must be no more than 128 characters.');
      return;
    }
    if (!_isStrongPassword(password)) {
      _showError(
        'Password must contain an uppercase letter, a lowercase letter, and a number.',
      );
      return;
    }
    if (confirm.isEmpty) {
      _showError('Please confirm your password.');
      return;
    }
    if (password != confirm) {
      _showError('Passwords do not match.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await AuthScope.of(context).register(
        firstName: firstName,
        lastName: lastName,
        email: email,
        password: password,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Account created. Check your email for the verification code.',
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.white),
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          duration: const Duration(seconds: 3),
        ),
      );
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 320),
          pageBuilder: (_, _, _) => VerificationCodeScreen(
            email: email,
            purpose: VerificationPurpose.emailVerification,
          ),
          transitionsBuilder: (_, anim, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: child,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      _showError(handleFormError(error));
      if (error.code == 'EMAIL_NOT_VERIFIED') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => VerificationCodeScreen(
              email: email,
              purpose: VerificationPurpose.emailVerification,
            ),
          ),
        );
      }
    } catch (_) {
      _showError('Unable to create your account right now. Please try again.');
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: true,
      appBar: Navigator.of(context).canPop()
          ? AppBar(
              backgroundColor: _bg,
              elevation: 0,
              toolbarHeight: 40,
              leading: const BackButton(color: _titleColor),
            )
          : null,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: AuthFormScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Title ───────────────────────────────────────
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'Sign ',
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: _titleColor,
                        ),
                      ),
                      TextSpan(
                        text: 'Up',
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.w400,
                          color: _titleColor,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Card — 20px side margins ─────────────────────
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
        borderRadius: BorderRadius.circular(8),
        // No shadow — flat card matches wireframe
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── First Name ───────────────────────────────────
          _fieldLabel('First Name'),
          const SizedBox(height: 4),
          AuthTextField(
            controller: _firstNameCtrl,
            keyboardType: TextInputType.name,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.givenName],
          ),

          const SizedBox(height: 10),

          // ── Last Name ────────────────────────────────────
          _fieldLabel('Last Name'),
          const SizedBox(height: 4),
          AuthTextField(
            controller: _lastNameCtrl,
            keyboardType: TextInputType.name,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.familyName],
          ),

          const SizedBox(height: 10),

          // ── Email ────────────────────────────────────────
          _fieldLabel('Email'),
          const SizedBox(height: 4),
          AuthTextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
          ),

          const SizedBox(height: 10),

          // ── Password ─────────────────────────────────────
          _fieldLabel('Password'),
          const SizedBox(height: 4),
          AuthTextField(
            controller: _passwordCtrl,
            obscureText: true,
            showVisibilityToggle: true,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
          ),

          const SizedBox(height: 10),

          // ── Confirm Password ──────────────────────────────
          _fieldLabel('Confirm Password'),
          const SizedBox(height: 4),
          AuthTextField(
            controller: _confirmCtrl,
            obscureText: true,
            showVisibilityToggle: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _createAccount(),
            autofillHints: const [AutofillHints.newPassword],
          ),

          const SizedBox(height: 12),

          // ── Sign Up button ────────────────────────────────
          _signUpButton(),
          AuthRetryNotice(seconds: retrySeconds),

          const SizedBox(height: 10),

          // ── Already have an account — INSIDE the card ─────
          // Wireframe: this row is at the bottom of the teal card,
          // not below it. Wrap only if a narrow viewport cannot fit the line.
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Already have an account? ',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Text(
                    'Log In',
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

  Widget _signUpButton() {
    return GestureDetector(
      onTap: _isLoading || isRateLimited ? null : _createAccount,
      child: Container(
        width: double.infinity,
        height: 36,
        decoration: BoxDecoration(
          color: _btnColor,
          borderRadius: BorderRadius.circular(4),
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
                  'Sign Up',
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
