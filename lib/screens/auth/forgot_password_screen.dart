// LOCATION: lib/screens/auth/forgot_password_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../constants/app_colors.dart';
import 'verification_code_screen.dart';
import 'widgets/auth_text_field.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState
    extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();

  bool _isLoading = false;

  // Same colors as Login Screen
  static const Color _bg = Color(0xFFDBE9EE);
  static const Color _cardColor = Color(0xFF1B6D8C);
  static const Color _btnColor = Color(0xFF5BB8D4);
  static const Color _titleBold = Color(0xFF166088);
  static const Color _titleLight = Color(0xFF4A6FA5);

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _fadeAnim = CurvedAnimation(
      parent: _fadeCtrl,
      curve: Curves.easeOut,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fadeCtrl.forward();
      }
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    final regex = RegExp(
      r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$',
    );

    return regex.hasMatch(email);
  }

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();

    if (email.isEmpty) {
      _showSnack('Please enter your email.');
      return;
    }

    if (!_isValidEmail(email)) {
      _showSnack('Please enter a valid email.');
      return;
    }

    setState(() => _isLoading = true);

    await Future.delayed(
      const Duration(milliseconds: 900),
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Verification code sent.',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 12,
          ),
        ),
        backgroundColor: _cardColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );

    await Future.delayed(
      const Duration(milliseconds: 350),
    );

    if (!mounted) return;

    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration:
            const Duration(milliseconds: 350),
        pageBuilder: (_, __, ___) =>
            VerificationCodeScreen(
          email: email,
        ),
        transitionsBuilder:
            (_, animation, __, child) =>
                FadeTransition(
          opacity: animation,
          child: child,
        ),
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
          backgroundColor: _cardColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SingleChildScrollView(
            physics:
                const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    MediaQuery.of(context)
                            .size
                            .height -
                        MediaQuery.of(context)
                            .padding
                            .top -
                        MediaQuery.of(context)
                            .padding
                            .bottom,
              ),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    const SizedBox(height: 20),

                    Align(
                      alignment:
                          Alignment.centerLeft,
                      child: IconButton(
                        icon: const Icon(
                          Icons.arrow_back_ios_new,
                          color: _titleBold,
                          size: 22,
                        ),
                        onPressed: () =>
                            Navigator.pop(context),
                      ),
                    ),

                    const SizedBox(height: 8),

                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'Forgot ',
                            style:
                                GoogleFonts.poppins(
                              fontSize: 28,
                              fontWeight:
                                  FontWeight.w700,
                              color: _titleBold,
                            ),
                          ),
                          TextSpan(
                            text: 'Password?',
                            style:
                                GoogleFonts.poppins(
                              fontSize: 28,
                              fontWeight:
                                  FontWeight.w400,
                              color: _titleLight,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      'No worries, we got you.',
                      style:
                          GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),

                    const SizedBox(height: 22),

                    Padding(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      child: Container(
                        width: double.infinity,
                        padding:
                            const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _cardColor,
                          borderRadius:
                              BorderRadius.circular(
                                  8),
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            Text(
                              'Email Address',
                              style:
                                  GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),

                            const SizedBox(
                                height: 5),

                            AuthTextField(
                              controller:
                                  _emailCtrl,
                              keyboardType:
                                  TextInputType
                                      .emailAddress,
                              textInputAction:
                                  TextInputAction
                                      .done,
                              autofillHints: const [
                                AutofillHints.email,
                              ],
                            ),

                            const SizedBox(
                                height: 16),

                            GestureDetector(
                              onTap: _isLoading
                                  ? null
                                  : _sendCode,
                              child: Container(
                                width:
                                    double.infinity,
                                height: 36,
                                decoration:
                                    BoxDecoration(
                                  color: _btnColor,
                                  borderRadius:
                                      BorderRadius
                                          .circular(
                                              4),
                                ),
                                child: Center(
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 16,
                                          height:
                                              16,
                                          child:
                                              CircularProgressIndicator(
                                            strokeWidth:
                                                2,
                                            valueColor:
                                                AlwaysStoppedAnimation(
                                              Colors
                                                  .white,
                                            ),
                                          ),
                                        )
                                      : Text(
                                          'Send',
                                          style:
                                              GoogleFonts.poppins(
                                            color: Colors
                                                .white,
                                            fontWeight:
                                                FontWeight
                                                    .w600,
                                            fontSize:
                                                14,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}