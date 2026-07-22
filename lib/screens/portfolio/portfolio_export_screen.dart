// LOCATION: lib/screens/portfolio/portfolio_export_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/grad_app_bar.dart';

import 'models/portfolio_models.dart';
import 'portfolio_preview_screen.dart';
import 'widgets/export_option_card.dart';
import 'widgets/step_indicator.dart';

/// Screen 3 of 3 — Export Portfolio.
/// Lets the user choose PDF or DOCX, then opens the Portfolio Preview screen.
class PortfolioExportScreen extends StatefulWidget {
  const PortfolioExportScreen({
    super.key,
    required this.portfolioInfo,
    required this.summary,
  });

  final PortfolioInfo portfolioInfo;
  final PortfolioSummary summary;

  @override
  State<PortfolioExportScreen> createState() =>
      _PortfolioExportScreenState();
}

class _PortfolioExportScreenState extends State<PortfolioExportScreen>
    with SingleTickerProviderStateMixin {
  ExportFormat _selectedFormat = ExportFormat.pdf;
  bool _isExporting = false;

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

    _slideAnim = Tween<Offset>(
      begin: const Offset(0.04, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entranceCtrl.forward();
    });
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Export action
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _onExport() async {
    setState(() => _isExporting = true);

    await Future.delayed(const Duration(milliseconds: 700));

    if (!mounted) return;

    setState(() => _isExporting = false);

    _showPreviewDialog();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Preview dialog
  // ─────────────────────────────────────────────────────────────────────────────
  void _showPreviewDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                color: AppColors.success,
                size: 38,
              ),
            ),
            const SizedBox(height: 16),

            Text(
              'Portfolio Ready',
              style: AppTextStyles.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),

            Text(
              'Your portfolio is ready for preview.',
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            Text(
              'Selected format: ${_selectedFormat.label}',
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  Navigator.pop(context);

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PortfolioPreviewScreen(
                        portfolioInfo: widget.portfolioInfo,
                        summary: widget.summary,
                      ),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  'Preview Portfolio',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────────
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
                  child: Column(
                    children: [
                      _buildExportCard(),
                      const SizedBox(height: 28),

                      _ExportButton(
                        isLoading: _isExporting,
                        onPressed: _onExport,
                      ),
                    ],
                  ),
                ),
              ),

              _buildStepBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExportCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Export Portfolio', style: AppTextStyles.h3),
          const SizedBox(height: 4),

          Text(
            'Choose the file format you want to export.',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 20),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: IntrinsicHeight(
                  child: ExportOptionCard(
                    format: ExportFormat.pdf,
                    isSelected: _selectedFormat == ExportFormat.pdf,
                    onTap: () =>
                        setState(() => _selectedFormat = ExportFormat.pdf),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: IntrinsicHeight(
                  child: ExportOptionCard(
                    format: ExportFormat.docx,
                    isSelected: _selectedFormat == ExportFormat.docx,
                    onTap: () =>
                        setState(() => _selectedFormat = ExportFormat.docx),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepBar() {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: const StepIndicatorLight(currentStep: 3),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────────
// Export button
// ───────────────────────────────────────────────────────────────────────────────
class _ExportButton extends StatefulWidget {
  const _ExportButton({
    required this.onPressed,
    this.isLoading = false,
  });

  final VoidCallback onPressed;
  final bool isLoading;

  @override
  State<_ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends State<_ExportButton>
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
      onTap: widget.isLoading ? null : widget.onPressed,
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
            child: widget.isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    'Export Portfolio',
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