// LOCATION: lib/screens/portfolio/portfolio_summary_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/grad_app_bar.dart';
import 'models/portfolio_models.dart';
import 'portfolio_export_screen.dart';
import 'widgets/section_counter_row.dart';
import 'widgets/step_indicator.dart';
import 'widgets/portfolio_documents_builder.dart';

/// Screen 2 of 3 — Portfolio Summary.
/// Displays total items and a breakdown of sections included.
/// Uses the authenticated user's current document counts.
class PortfolioSummaryScreen extends StatefulWidget {
  const PortfolioSummaryScreen({super.key, required this.portfolio});

  final PortfolioRecord portfolio;

  @override
  State<PortfolioSummaryScreen> createState() => _PortfolioSummaryScreenState();
}

class _PortfolioSummaryScreenState extends State<PortfolioSummaryScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceCtrl,
            curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
          ),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entranceCtrl.forward();
    });
  }

  bool _isNavigating = false;

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  void _onNext() async {
    if (_isNavigating) return;
    _isNavigating = true;
    try {
      await Navigator.push(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 350),
          pageBuilder: (_, _, _) =>
              PortfolioExportScreen(portfolioInfo: widget.portfolio.info),
          transitionsBuilder: (_, anim, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0.05, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
                  ),
              child: child,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) _isNavigating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: GradBackAppBar(
        title: 'Generate Portfolio',
        onBack: () => Navigator.pop(context),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: PortfolioDocumentsBuilder(
                    builder: (documents) {
                      final summary = PortfolioSummary.fromDocumentSummary(
                        documents.summary,
                      );
                      return Column(
                        children: [
                          // ── Portfolio Summary stat card ────────────────
                          _buildSummaryCard(summary),

                          const SizedBox(height: 20),

                          // ── Sections Included card ─────────────────────
                          _buildSectionsCard(summary),

                          const SizedBox(height: 28),

                          // ── Next button ────────────────────────────────
                          _PortfolioActionButton(
                            label: 'Next',
                            onPressed: _onNext,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),

              // ── Step indicator ─────────────────────────────────────
              _buildStepBar(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Portfolio Summary stat card ───────────────────────────────────────────
  Widget _buildSummaryCard(PortfolioSummary summary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Portfolio Summary',
            style: AppTextStyles.h3.copyWith(color: AppColors.primary),
          ),
          const SizedBox(height: 4),
          Text(
            widget.portfolio.info.formattedSchedule,
            style: AppTextStyles.labelMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text('Total Items', style: AppTextStyles.labelMedium),
          const SizedBox(height: 4),
          // Animated count
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: summary.totalItems),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOut,
            builder: (_, value, _) => Text(
              value.toString(),
              key: const Key('portfolio-total-items'),
              style: GoogleFonts.poppins(
                fontSize: 48,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sections Included card ────────────────────────────────────────────────
  Widget _buildSectionsCard(PortfolioSummary summary) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Center(
              child: Text(
                'Sections Included',
                style: AppTextStyles.h4.copyWith(color: AppColors.primary),
              ),
            ),
          ),

          // Section rows
          ...summary.sections.asMap().entries.map((entry) {
            final isLast = entry.key == summary.sections.length - 1;
            return SectionCounterRow(
              key: ValueKey('section-${entry.value.name}'),
              name: entry.value.name,
              count: entry.value.count,
              isLast: isLast,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStepBar() {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: const StepIndicatorLight(currentStep: 2),
    );
  }
}

// ─── Reusable action button for portfolio flow screens ────────────────────────
class _PortfolioActionButton extends StatefulWidget {
  const _PortfolioActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_PortfolioActionButton> createState() => _PortfolioActionButtonState();
}

class _PortfolioActionButtonState extends State<_PortfolioActionButton>
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
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.97,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
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
