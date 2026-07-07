// LOCATION: lib/screens/auth/verification_code_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'new_password_screen.dart';

class VerificationCodeScreen extends StatefulWidget {
  const VerificationCodeScreen({super.key, required this.email});

  final String email;

  @override
  State<VerificationCodeScreen> createState() =>
      _VerificationCodeScreenState();
}

class _VerificationCodeScreenState extends State<VerificationCodeScreen>
    with SingleTickerProviderStateMixin {
  // One controller + focus node per digit box
  final List<TextEditingController> _ctrls =
      List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(4, (_) => FocusNode());

  bool _isLoading = false;

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
      if (mounted) {
        _fadeCtrl.forward();
        // Auto-focus first box
        _focusNodes[0].requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (final c in _ctrls)      { c.dispose(); }
    for (final f in _focusNodes) { f.dispose(); }
    _fadeCtrl.dispose();
    super.dispose();
  }

  String get _code => _ctrls.map((c) => c.text).join();

  bool get _isComplete => _code.length == 4 && !_code.contains('');

  // Called on every keystroke in a digit box
  void _onChanged(String value, int index) {
    if (value.isEmpty) return;
    // Only keep last character (in case of paste or IME)
    final digit = value[value.length - 1];
    _ctrls[index].text = digit;
    _ctrls[index].selection = TextSelection.collapsed(offset: 1);

    if (index < 3) {
      _focusNodes[index + 1].requestFocus();
    } else {
      _focusNodes[index].unfocus();
    }
    setState(() {});
  }

  // Handle backspace — go to previous box
  void _onKeyEvent(KeyEvent event, int index) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_ctrls[index].text.isEmpty && index > 0) {
        _ctrls[index - 1].clear();
        _focusNodes[index - 1].requestFocus();
        setState(() {});
      }
    }
  }

  Future<void> _onContinue() async {
    if (!_isComplete) {
      _showError('Please enter the complete 4-digit code.');
      return;
    }

    setState(() => _isLoading = true);
    // DEVELOPMENT ONLY — mock delay; replace with real verification in Capstone 2
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _isLoading = false);

    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, __, ___) => const NewPasswordScreen(),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  void _onResend() {
    // Clear all boxes and re-focus first
    for (final c in _ctrls) { c.clear(); }
    _focusNodes[0].requestFocus();
    setState(() {});

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(
          'Verification code sent.',
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.white),
        ),
        backgroundColor: _cardColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 3),
      ));
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
                            'Verification Code',
                            style: GoogleFonts.poppins(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: _titleBold,
                            ),
                          ),

                          const SizedBox(height: 6),

                          // ── Subtitle ──────────────────────────────
                          Text(
                            'We sent a code to your email.',
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
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Instruction ──────────────────────────────────────
          Text(
            'Enter the code to continue',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 14),

          // ── OTP boxes ────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) {
              return Padding(
                padding: EdgeInsets.only(right: i < 3 ? 12 : 0),
                child: _OtpBox(
                  controller: _ctrls[i],
                  focusNode:  _focusNodes[i],
                  onChanged:  (v) => _onChanged(v, i),
                  onKeyEvent: (e) => _onKeyEvent(e, i),
                ),
              );
            }),
          ),

          const SizedBox(height: 18),

          // ── Continue button ───────────────────────────────────
          _continueButton(),

          const SizedBox(height: 12),

          // ── Resend ────────────────────────────────────────────
          Center(
            child: GestureDetector(
              onTap: _onResend,
              child: Text(
                'Resend Code',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _continueButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _onContinue,
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
                  'Continue',
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

// ─── Single OTP digit box ─────────────────────────────────────────────────────
class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onKeyEvent,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<KeyEvent> onKeyEvent;

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: onKeyEvent,
      child: SizedBox(
        width: 52,
        height: 52,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
          ),
          child: TextField(
            controller:   controller,
            focusNode:    focusNode,
            onChanged:    onChanged,
            keyboardType: TextInputType.number,
            textAlign:    TextAlign.center,
            maxLength:    1,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A2E35),
            ),
            decoration: const InputDecoration(
              counterText: '',
              isDense:     true,
              filled:      true,
              fillColor:   Colors.transparent,
              contentPadding: EdgeInsets.zero,
              border:        InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
      ),
    );
  }
}