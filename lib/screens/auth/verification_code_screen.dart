import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_client.dart';
import '../../services/auth_models.dart';
import '../../services/auth_scope.dart';
import 'login_screen.dart';
import 'new_password_screen.dart';

class VerificationCodeScreen extends StatefulWidget {
  final String email;
  final VerificationPurpose purpose;

  const VerificationCodeScreen({
    super.key,
    required this.email,
    required this.purpose,
  });

  @override
  State<VerificationCodeScreen> createState() => _VerificationCodeScreenState();
}

class _VerificationCodeScreenState extends State<VerificationCodeScreen>
    with SingleTickerProviderStateMixin {
  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isLoading = false;
  bool _isResending = false;
  int _resendSeconds = 60;
  Timer? _resendTimer;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  static const Color _bgColor = Color(0xFFCFE2ED);
  static const Color _darkTeal = Color(0xFF1A4F72);
  static const Color _accentColor = Color(0xFF1E7BAE);
  static const Color _subtitleColor = Color(0xFF1E7BAE);
  static const Color _boxBorder = Color(0xFFB0CDD9);
  static const Color _boxActiveBorder = Color(0xFF1E7BAE);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
    _startResendTimer();
  }

  void _startResendTimer() {
    _resendSeconds = 60;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_resendSeconds > 0) {
          _resendSeconds--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _resendTimer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _otpValue => _controllers.map((c) => c.text).join();

  bool get _isComplete => _otpValue.length == 6;

  void _onDigitChanged(int index, String value) {
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      if (digits.isEmpty) return;
      for (int i = 0; i < 6 && i < digits.length; i++) {
        _controllers[i].text = digits[i];
      }
      final nextFocus = (digits.length < 6) ? digits.length : 5;
      _focusNodes[nextFocus].requestFocus();
      setState(() {});
      return;
    }

    if (value.isNotEmpty) {
      _controllers[index].text = value;
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
    }
    setState(() {});
  }

  KeyEventResult _onKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_controllers[index].text.isEmpty && index > 0) {
        _controllers[index - 1].clear();
        _focusNodes[index - 1].requestFocus();
        setState(() {});
      } else {
        _controllers[index].clear();
        setState(() {});
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _handleContinue() async {
    if (!_isComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the 6-digit code')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      if (widget.purpose == VerificationPurpose.emailVerification) {
        await AuthScope.of(
          context,
        ).verifyEmail(email: widget.email, code: _otpValue);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email verified. You can now log in.')),
        );
        Navigator.of(context).pushAndRemoveUntil(
          PageRouteBuilder(
            pageBuilder: (_, animation, __) => const LoginScreen(),
            transitionsBuilder: (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 350),
          ),
          (route) => false,
        );
      } else {
        final resetToken = await AuthScope.of(
          context,
        ).verifyPasswordReset(email: widget.email, code: _otpValue);
        if (!mounted) return;
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (_, animation, __) =>
                NewPasswordScreen(resetToken: resetToken),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position:
                      Tween<Offset>(
                        begin: const Offset(1, 0),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOut,
                        ),
                      ),
                  child: child,
                ),
              );
            },
            transitionDuration: const Duration(milliseconds: 350),
          ),
        );
      }
    } on ApiException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Unable to verify the code right now. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleResend() async {
    if (_resendSeconds > 0 || _isResending) return;
    setState(() => _isResending = true);
    try {
      final auth = AuthScope.of(context);
      if (widget.purpose == VerificationPurpose.emailVerification) {
        await auth.resendEmailVerification(email: widget.email);
      } else {
        await auth.resendPasswordReset(email: widget.email);
      }
      if (!mounted) return;
      _startResendTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Code resent to ${widget.email}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } on ApiException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Unable to resend the code right now. Please try again.');
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 8),
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: _darkTeal,
                      size: 20,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight:
                              MediaQuery.of(context).size.height -
                              MediaQuery.of(context).padding.top -
                              90,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(
                              text: const TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'Verification ',
                                    style: TextStyle(
                                      color: Color(0xFF1A4F72),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 28,
                                    ),
                                  ),
                                  TextSpan(
                                    text: 'Code',
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 28,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 8),

                            const Text(
                              'We sent a code to your email.',
                              style: TextStyle(
                                color: _subtitleColor,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),

                            const SizedBox(height: 40),

                            const Text(
                              'Enter the code to continue',
                              style: TextStyle(
                                color: _darkTeal,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),

                            const SizedBox(height: 16),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: List.generate(
                                6,
                                (index) => _buildOtpBox(index),
                              ),
                            ),

                            const SizedBox(height: 36),

                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _handleContinue,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _accentColor,
                                  foregroundColor: Colors.white,
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Continue',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                              ),
                            ),

                            const SizedBox(height: 18),

                            Center(
                              child: GestureDetector(
                                onTap: _resendSeconds == 0
                                    ? _handleResend
                                    : null,
                                child: Text(
                                  _resendSeconds > 0
                                      ? 'Resend Code (${_resendSeconds}s)'
                                      : 'Resend Code',
                                  style: TextStyle(
                                    color: _resendSeconds > 0
                                        ? const Color(0xFF8BB5C8)
                                        : _accentColor,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    decoration: _resendSeconds == 0
                                        ? TextDecoration.underline
                                        : TextDecoration.none,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOtpBox(int index) {
    final isFilled = _controllers[index].text.isNotEmpty;
    return SizedBox(
      width: 42,
      height: 56,
      child: Focus(
        onKeyEvent: (_, event) => _onKeyEvent(index, event),
        child: TextFormField(
          controller: _controllers[index],
          focusNode: _focusNodes[index],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            color: _darkTeal,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: Colors.white,
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _boxBorder, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: isFilled ? _boxActiveBorder : _boxBorder,
                width: isFilled ? 2 : 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _boxActiveBorder, width: 2),
            ),
          ),
          onChanged: (value) => _onDigitChanged(index, value),
        ),
      ),
    );
  }
}
