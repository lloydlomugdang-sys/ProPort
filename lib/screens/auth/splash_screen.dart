// LOCATION: lib/screens/auth/splash_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../constants/app_colors.dart';
import '../../services/auth_scope.dart';
import '../../services/auth_service.dart';
import '../main_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _textFade;
  late final Animation<double> _lineFade;
  bool _restoreStarted = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _logoScale = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.50, curve: Curves.easeOutBack),
      ),
    );
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.40, curve: Curves.easeOut),
      ),
    );
    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.35, 0.65, curve: Curves.easeOut),
      ),
    );
    _lineFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.55, 0.90, curve: Curves.easeOut),
      ),
    );

    _ctrl.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restoreStarted) return;
    _restoreStarted = true;
    _completeStartup();
  }

  Future<void> _completeStartup() async {
    final minimumSplashTime = Future<void>.delayed(
      const Duration(milliseconds: 2000),
    );
    final result = await AuthScope.of(context).restoreSession();
    await minimumSplashTime;
    if (!mounted) return;

    final destination = result == SessionRestoreResult.authenticated
        ? const MainScreen()
        : LoginScreen(
            initialMessage: result == SessionRestoreResult.unavailable
                ? 'Unable to restore your session right now. Please log in or try again later.'
                : null,
          );
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        settings: RouteSettings(
          name: destination is MainScreen ? MainScreen.routeName : null,
        ),
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, _, _) => destination,
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFDBE9EE),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Logo — large, ~50% of narrower screens ────────────
            ScaleTransition(
              scale: _logoScale,
              child: FadeTransition(
                opacity: _logoFade,
                child: Image.asset(
                  'assets/images/proport_logo.png',
                  width: 160,
                  height: 160,
                  fit: BoxFit.contain,
                ),
              ),
            ),

            const SizedBox(height: 10),

            // ── "GradPort" wordmark ────────────────────────────────
            FadeTransition(
              opacity: _textFade,
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Grad',
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    TextSpan(
                      text: 'Port',
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w400,
                        color: AppColors.neutral,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // ── Short teal divider line — matches wireframe ────────
            // No spinner. No tagline.
            FadeTransition(
              opacity: _lineFade,
              child: Container(
                width: 80,
                height: 2.5,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
