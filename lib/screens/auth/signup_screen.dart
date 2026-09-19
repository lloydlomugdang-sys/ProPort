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
import 'login_screen.dart';
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
      _showError('Please enter a password.');
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
        'Password must contain an uppercase letter, lowercase letter, and number.',
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
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
      );
      if (!mounted) return;
      Navigator.push(
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
      if (error.code == 'EMAIL_NOT_VERIFIED') {
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
      } else {
        _showError(handleFormError(error));
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
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      appBar: canPop
          ? AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
              toolbarHeight: 44,
              leading: const BackButton(color: AppColors.textPrimary),
            )
          : null,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: AuthFormScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Title & Subtitle matching mockup ───────────
                  Text(
                    'Create Your Account',
                    style: GoogleFonts.poppins(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Start building your portfolio today.',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Form Surface Card ──────────────────────────
                  _buildFormCard(),

                  const SizedBox(height: 24),

                  // ── Already have an account? Log In ────────────
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Already have an account? ',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            if (canPop) {
                              Navigator.pop(context);
                            } else {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const LoginScreen(),
                                ),
                              );
                            }
                          },
                          child: Text(
                            'Log In',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── First Name ───────────────────────────────────
          _fieldLabel('First Name'),
          const SizedBox(height: 6),
          AuthTextField(
            controller: _firstNameCtrl,
            keyboardType: TextInputType.name,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.givenName],
            hintText: 'Enter your first name',
            prefixIcon: const Icon(
              Icons.person_outline,
              size: 20,
              color: AppColors.primary,
            ),
          ),

          const SizedBox(height: 14),

          // ── Last Name ────────────────────────────────────
          _fieldLabel('Last Name'),
          const SizedBox(height: 6),
          AuthTextField(
            controller: _lastNameCtrl,
            keyboardType: TextInputType.name,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.familyName],
            hintText: 'Enter your last name',
            prefixIcon: const Icon(
              Icons.person_outline,
              size: 20,
              color: AppColors.primary,
            ),
          ),

          const SizedBox(height: 14),

          // ── Email ────────────────────────────────────────
          _fieldLabel('Email'),
          const SizedBox(height: 6),
          AuthTextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            hintText: 'Enter your email address',
            prefixIcon: const Icon(
              Icons.email_outlined,
              size: 20,
              color: AppColors.primary,
            ),
          ),

          const SizedBox(height: 14),

          // ── Password ─────────────────────────────────────
          _fieldLabel('Password'),
          const SizedBox(height: 6),
          AuthTextField(
            controller: _passwordCtrl,
            obscureText: true,
            showVisibilityToggle: true,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            hintText: 'Create a password',
            prefixIcon: const Icon(
              Icons.lock_outline,
              size: 20,
              color: AppColors.primary,
            ),
          ),

          const SizedBox(height: 14),

          // ── Confirm Password ──────────────────────────────
          _fieldLabel('Confirm Password'),
          const SizedBox(height: 6),
          AuthTextField(
            controller: _confirmCtrl,
            obscureText: true,
            showVisibilityToggle: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _createAccount(),
            autofillHints: const [AutofillHints.newPassword],
            hintText: 'Confirm your password',
            prefixIcon: const Icon(
              Icons.lock_outline,
              size: 20,
              color: AppColors.primary,
            ),
          ),

          const SizedBox(height: 20),

          // ── Sign Up button ────────────────────────────────
          _signUpButton(),
          AuthRetryNotice(seconds: retrySeconds),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) => Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      );

  Widget _signUpButton() {
    return GestureDetector(
      onTap: _isLoading || isRateLimited ? null : _createAccount,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: AppColors.primaryGradient,
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.28),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  'Sign Up',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
        ),
      ),
    );
  }
}
