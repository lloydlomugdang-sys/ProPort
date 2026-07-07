// LOCATION: lib/screens/auth/new_password_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'login_screen.dart';

class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({super.key});

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _newPwCtrl     = TextEditingController();
  final _confirmPwCtrl = TextEditingController();

  bool _newHidden     = true;
  bool _confirmHidden = true;
  bool _isLoading     = false;

  static const Color _bg        = Color(0xFFDBE9EE);
  static const Color _cardColor = Color(0xFF1B6D8C);
  static const Color _btnColor  = Color(0xFF5BB8D4);
  static const Color _titleBold = Color(0xFF166088);

  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fadeAnim;

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
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    final newPw   = _newPwCtrl.text.trim();
    final confirm = _confirmPwCtrl.text.trim();

    if (newPw.isEmpty) {
      _showError('Please enter a new password.');
      return;
    }
    if (newPw.length < 8) {
      _showError('Password must be at least 8 characters.');
      return;
    }
    if (confirm.isEmpty) {
      _showError('Please confirm your password.');
      return;
    }
    if (newPw != confirm) {
      _showError('Passwords do not match.');
      return;
    }

    setState(() => _isLoading = true);
    // DEVELOPMENT ONLY — mock delay; replace with real API call in Capstone 2
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(
          'Password updated successfully.',
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF27AE60),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 2),
      ));

    // Navigate back to Login, clearing the entire forgot-password stack
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => const LoginScreen(),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      ),
      (route) => false,
    );
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
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Back button ──────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new,
                            size: 20, color: Color(0xFF166088)),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),

                    const Spacer(),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // ── Heading ───────────────────────────────
                          Text(
                            'New Password',
                            style: GoogleFonts.poppins(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: _titleBold,
                            ),
                          ),

                          const SizedBox(height: 6),

                          // ── Subtitle ──────────────────────────────
                          Text(
                            'Create a unique password.',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF4A6FA5),
                            ),
                          ),

                          const SizedBox(height: 22),

                          // ── Card ──────────────────────────────────
                          _buildCard(),
                        ],
                      ),
                    ),

                    const Spacer(),
                    const SizedBox(height: 24),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── New Password ─────────────────────────────────────
          _fieldLabel('New Password'),
          const SizedBox(height: 4),
          _passwordField(
            controller:  _newPwCtrl,
            isHidden:    _newHidden,
            onToggle:    () => setState(() => _newHidden = !_newHidden),
            action:      TextInputAction.next,
          ),

          const SizedBox(height: 10),

          // ── Confirm Password ──────────────────────────────────
          _fieldLabel('Confirm Password'),
          const SizedBox(height: 4),
          _passwordField(
            controller:  _confirmPwCtrl,
            isHidden:    _confirmHidden,
            onToggle:    () =>
                setState(() => _confirmHidden = !_confirmHidden),
            action:      TextInputAction.done,
            onSubmitted: (_) => _onSave(),
          ),

          const SizedBox(height: 14),

          // ── Save button ───────────────────────────────────────
          _saveButton(),
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

  // Password field — white box + visibility toggle, matches auth screens
  Widget _passwordField({
    required TextEditingController controller,
    required bool isHidden,
    required VoidCallback onToggle,
    required TextInputAction action,
    ValueChanged<String>? onSubmitted,
  }) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller:     controller,
              obscureText:    isHidden,
              textInputAction: action,
              onSubmitted:    onSubmitted,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF1A2E35),
              ),
              decoration: const InputDecoration(
                isDense:    true,
                filled:     true,
                fillColor:  Colors.transparent,
                contentPadding: EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                border:        InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          // Visibility toggle
          GestureDetector(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                isHidden
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size:  18,
                color: const Color(0xFF8FAAB5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _saveButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _onSave,
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
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  'Save Password',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}