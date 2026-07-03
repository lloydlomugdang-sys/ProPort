// LOCATION: lib/screens/auth/signup_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../constants/app_colors.dart';
import 'widgets/auth_text_field.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl  = TextEditingController();
  final _emailCtrl     = TextEditingController();
  final _passwordCtrl  = TextEditingController();
  final _confirmCtrl   = TextEditingController();
  bool  _isLoading     = false;

  static const Color _bg         = Color(0xFFDBE9EE);
  static const Color _cardColor  = Color(0xFF1B6D8C);
  static const Color _btnColor   = Color(0xFF5BB8D4);
  static const Color _titleBold  = Color(0xFF166088);
  static const Color _titleLight = Color(0xFF4A6FA5);

  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _fadeAnim = CurvedAnimation(
      parent: _fadeCtrl,
      curve: Curves.easeOut,
    );
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

  // DEVELOPMENT ONLY — mock sign-up; replace with real service in Capstone 2
  Future<void> _createAccount() async {
    if (_firstNameCtrl.text.trim().isEmpty) {
      _showError('Please enter your first name.'); return;
    }
    if (_lastNameCtrl.text.trim().isEmpty) {
      _showError('Please enter your last name.'); return;
    }
    if (_emailCtrl.text.trim().isEmpty) {
      _showError('Please enter your email.'); return;
    }
    if (_passwordCtrl.text.trim().isEmpty) {
      _showError('Please enter a password.'); return;
    }
    if (_confirmCtrl.text.trim().isEmpty) {
      _showError('Please confirm your password.'); return;
    }
    if (_passwordCtrl.text.trim() != _confirmCtrl.text.trim()) {
      _showError('Passwords do not match.'); return;
    }

    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        'Account created successfully (Development Mode)',
        style: GoogleFonts.poppins(fontSize: 12, color: Colors.white),
      ),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      margin:   const EdgeInsets.fromLTRB(16, 0, 16, 16),
      duration: const Duration(seconds: 3),
    ));

    Navigator.pop(context);
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg,
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.white)),
        backgroundColor: _cardColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        margin:   const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 3),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          // SingleChildScrollView prevents overflow on small screens /
          // when keyboard is up. ConstrainedBox + IntrinsicHeight +
          // MainAxisAlignment.center gives vertical centering when the
          // card is shorter than the available height.
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.top -
                    MediaQuery.of(context).padding.bottom,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ── Title ───────────────────────────────────────
                    RichText(
                      text: TextSpan(children: [
                        TextSpan(
                          text: 'Sign ',
                          style: GoogleFonts.poppins(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: _titleBold,
                          ),
                        ),
                        TextSpan(
                          text: 'Up',
                          style: GoogleFonts.poppins(
                            fontSize: 28,
                            fontWeight: FontWeight.w400,
                            color: _titleLight,
                          ),
                        ),
                      ]),
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
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color:        _cardColor,
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
            controller:    _firstNameCtrl,
            keyboardType:  TextInputType.name,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.givenName],
          ),

          const SizedBox(height: 10),

          // ── Last Name ────────────────────────────────────
          _fieldLabel('Last Name'),
          const SizedBox(height: 4),
          AuthTextField(
            controller:    _lastNameCtrl,
            keyboardType:  TextInputType.name,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.familyName],
          ),

          const SizedBox(height: 10),

          // ── Email ────────────────────────────────────────
          _fieldLabel('Email'),
          const SizedBox(height: 4),
          AuthTextField(
            controller:    _emailCtrl,
            keyboardType:  TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
          ),

          const SizedBox(height: 10),

          // ── Password ─────────────────────────────────────
          _fieldLabel('Password'),
          const SizedBox(height: 4),
          AuthTextField(
            controller:    _passwordCtrl,
            obscureText:   true,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
          ),

          const SizedBox(height: 10),

          // ── Confirm Password ──────────────────────────────
          _fieldLabel('Confirm Password'),
          const SizedBox(height: 4),
          AuthTextField(
            controller:    _confirmCtrl,
            obscureText:   true,
            textInputAction: TextInputAction.done,
            onSubmitted:   (_) => _createAccount(),
            autofillHints: const [AutofillHints.newPassword],
          ),

          const SizedBox(height: 12),

          // ── Sign Up button ────────────────────────────────
          _signUpButton(),

          const SizedBox(height: 10),

          // ── Already have an account — INSIDE the card ─────
          // Wireframe: this row is at the bottom of the teal card,
          // not below it. Centering it here prevents any overflow.
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
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
      onTap: _isLoading ? null : _createAccount,
      child: Container(
        width:  double.infinity,
        height: 36,
        decoration: BoxDecoration(
          color:        _btnColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: _isLoading
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  'Sign Up',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color:     Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}