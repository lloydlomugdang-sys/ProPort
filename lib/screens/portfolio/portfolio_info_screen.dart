// LOCATION: lib/screens/portfolio/portfolio_info_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/grad_app_bar.dart';
import 'models/portfolio_models.dart';
import 'portfolio_summary_screen.dart';
import 'widgets/portfolio_text_field.dart';
import 'widgets/step_indicator.dart';

/// Screen 1 of 3 — Portfolio Information.
/// Collects title page fields before generating the portfolio.
class PortfolioInfoScreen extends StatefulWidget {
  const PortfolioInfoScreen({super.key});

  @override
  State<PortfolioInfoScreen> createState() => _PortfolioInfoScreenState();
}

class _PortfolioInfoScreenState extends State<PortfolioInfoScreen>
    with SingleTickerProviderStateMixin {
  // ─── Controllers ─────────────────────────────────────────────────────────────
  final _fullNameCtrl       = TextEditingController();
  final _yearSectionCtrl    = TextEditingController();
  final _scheduleCtrl       = TextEditingController();
  final _instructorCtrl     = TextEditingController();
  final _courseCtrl         = TextEditingController();
  final _courseCodeCtrl     = TextEditingController();
  final _semesterYearCtrl   = TextEditingController();

  // ─── Entrance animation ───────────────────────────────────────────────────────
  late final AnimationController _entranceCtrl;
  late final Animation<double>   _fadeAnim;
  late final Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entranceCtrl.forward();
    });
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _yearSectionCtrl.dispose();
    _scheduleCtrl.dispose();
    _instructorCtrl.dispose();
    _courseCtrl.dispose();
    _courseCodeCtrl.dispose();
    _semesterYearCtrl.dispose();
    _entranceCtrl.dispose();
    super.dispose();
  }

  // ─── Validation & navigation ──────────────────────────────────────────────────
  void _onNext() {
    // Validate required fields only
    if (_fullNameCtrl.text.trim().isEmpty) {
      _showError('Full Name is required.');
      return;
    }
    if (_yearSectionCtrl.text.trim().isEmpty) {
      _showError('Year & Section is required.');
      return;
    }
    if (_scheduleCtrl.text.trim().isEmpty) {
      _showError('Schedule is required.');
      return;
    }
    if (_instructorCtrl.text.trim().isEmpty) {
      _showError("Instructor's Name is required.");
      return;
    }

    // Build the model
    final info = PortfolioInfo(
      fullName:        _fullNameCtrl.text.trim(),
      yearAndSection:  _yearSectionCtrl.text.trim(),
      schedule:        _scheduleCtrl.text.trim(),
      instructorName:  _instructorCtrl.text.trim(),
      course:          _courseCtrl.text.trim(),
      courseCode:      _courseCodeCtrl.text.trim(),
      semesterAndYear: _semesterYearCtrl.text.trim(),
    );

    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, __, ___) =>
            PortfolioSummaryScreen(portfolioInfo: info),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.05, 0),
              end: Offset.zero,
            ).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white)),
      backgroundColor: AppColors.primary,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      duration: const Duration(seconds: 3),
    ));
  }

  // ─── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const GradBackAppBar(title: 'Generate Portfolio'),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Column(
            children: [
              // Scrollable form content
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Section label ──────────────────────────────
                      Text('Title Page', style: AppTextStyles.h3),
                      const SizedBox(height: 16),

                      // ── Full Name* ─────────────────────────────────
                      PortfolioTextField(
                        controller: _fullNameCtrl,
                        label: 'Full Name',
                        hint: 'Dela Cruz, John',
                        required: true,
                        keyboardType: TextInputType.name,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),

                      // ── Year & Section* ────────────────────────────
                      PortfolioTextField(
                        controller: _yearSectionCtrl,
                        label: 'Year & Section',
                        hint: 'e.g. 4BSIT-1',
                        required: true,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),

                      // ── Schedule* ──────────────────────────────────
                      PortfolioTextField(
                        controller: _scheduleCtrl,
                        label: 'Schedule',
                        hint: 'e.g. Monday 8:00AM - 9:30AM',
                        required: true,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),

                      // ── Instructor's Name* ─────────────────────────
                      PortfolioTextField(
                        controller: _instructorCtrl,
                        label: "Instructor's Name",
                        hint: 'First Name, Middle Initial, Last name',
                        required: true,
                        keyboardType: TextInputType.name,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),

                      // ── Course ─────────────────────────────────────
                      PortfolioTextField(
                        controller: _courseCtrl,
                        label: 'Course',
                        hint: 'Free Elective',
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),

                      // ── Course Code ────────────────────────────────
                      PortfolioTextField(
                        controller: _courseCodeCtrl,
                        label: 'Course Code',
                        hint: 'e.g. CCSFE4-18',
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),

                      // ── Semester & Academic Year ───────────────────
                      PortfolioTextField(
                        controller: _semesterYearCtrl,
                        label: 'Semester & Academic Year',
                        hint: 'e.g. 2nd Semester, A.Y. 2025-2026',
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _onNext(),
                      ),

                      const SizedBox(height: 28),

                      // ── Next button ────────────────────────────────
                      _NextButton(onPressed: _onNext),
                    ],
                  ),
                ),
              ),

              // ── Step indicator (pinned above bottom nav) ───────────
              _buildStepBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepBar() {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: const StepIndicatorLight(currentStep: 1),
    );
  }
}

// ─── Reusable Next / Action button for the portfolio flow ────────────────────
class _NextButton extends StatefulWidget {
  const _NextButton({required this.onPressed, this.label = 'Next'});
  final VoidCallback onPressed;
  final String label;

  @override
  State<_NextButton> createState() => _NextButtonState();
}

class _NextButtonState extends State<_NextButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) => _ctrl.reverse(),
      onTapCancel: () => _ctrl.reverse(),
      onTap: widget.onPressed,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Text(
              widget.label,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}