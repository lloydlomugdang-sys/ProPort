// LOCATION: lib/screens/portfolio/portfolio_preview_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/grad_app_bar.dart';
import '../../widgets/primary_button.dart';
import 'models/portfolio_models.dart';
import '../main_screen.dart';

/// Read-only preview of the generated portfolio, shown right before export.
/// Styled to resemble the first page of an academic PDF document rather
/// than a Canva-style editor — this is a static, print-like preview.
///
/// Uses mock/in-memory data (PortfolioInfo + PortfolioSummary) — replace
/// with real MongoDB / OCR-backed data when the backend is ready.
class PortfolioPreviewScreen extends StatelessWidget {
  const PortfolioPreviewScreen({
    super.key,
    required this.portfolioInfo,
    PortfolioSummary? summary,
    this.exportFormat = ExportFormat.pdf,
  }) : summary = summary ?? const PortfolioSummary(sections: []);

  final PortfolioInfo portfolioInfo;
  final PortfolioSummary summary;

  /// The export format selected earlier in the flow (defaults to PDF when
  /// not provided — shown in the success dialog "if available").
  final ExportFormat exportFormat;

  // ─── Actions ────────────────────────────────────────────────────────────
  void _onConfirmExport(BuildContext context) {
    // TODO(GradPort v2): real PDF/DOCX generation will be wired here.
    // For now, confirming shows a success dialog and returns to the
    // dashboard, clearing the entire portfolio flow from the stack.
    _showSuccessDialog(context);
  }

  void _showSuccessDialog(BuildContext context) {
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
            // Success icon
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
              'Portfolio Exported',
              style: AppTextStyles.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),

            Text(
              'Your portfolio has been exported successfully.',
              style: AppTextStyles.bodySmall.copyWith(
                height: 1.6,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),

            Text(
              'Format: ${exportFormat.label}',
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Back to Dashboard button
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  Navigator.pop(context); // close dialog
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const MainScreen()),
                    (route) => false,
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
                  'Back to Dashboard',
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

  @override
  Widget build(BuildContext context) {
    final sections = summary.sections.isNotEmpty
        ? summary.sections
        : PortfolioSummary.mock.sections;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: GradBackAppBar(
        title: 'Portfolio Preview',
        onBack: () => Navigator.pop(context),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: _PreviewSheet(
                      portfolioInfo: portfolioInfo,
                      sections: sections,
                    ),
                  ),
                ),
              ),
            ),

            // ── Bottom actions ─────────────────────────────────────────
            _buildBottomActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.divider),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: 'Back',
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: PrimaryButton(
                label: 'Confirm & Export',
                onPressed: () => _onConfirmExport(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── A4-like preview sheet ───────────────────────────────────────────────
class _PreviewSheet extends StatelessWidget {
  const _PreviewSheet({
    required this.portfolioInfo,
    required this.sections,
  });

  final PortfolioInfo portfolioInfo;
  final List<PortfolioSection> sections;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDocumentHeader(),
          const SizedBox(height: 24),
          _buildDivider(),
          const SizedBox(height: 20),
          _buildStudentInfoSection(),
          const SizedBox(height: 24),
          _buildSectionsIncluded(),
          const SizedBox(height: 24),
          _buildFooterNote(),
        ],
      ),
    );
  }

  // ── Document header ───────────────────────────────────────────────────
  Widget _buildDocumentHeader() {
    return Column(
      children: [
        Text(
          'NEW ERA UNIVERSITY',
          textAlign: TextAlign.center,
          style: AppTextStyles.h2.copyWith(
            color: AppColors.primary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'College of Informatics and Computing Studies',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'ACADEMIC PORTFOLIO',
          textAlign: TextAlign.center,
          style: AppTextStyles.h4.copyWith(
            color: AppColors.textPrimary,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(height: 1, color: AppColors.divider);
  }

  // ── Student information ───────────────────────────────────────────────
  Widget _buildStudentInfoSection() {
    final fields = <MapEntry<String, String>>[
      MapEntry('Full Name', portfolioInfo.fullName),
      MapEntry('Year & Section', portfolioInfo.yearAndSection),
      MapEntry('Schedule', portfolioInfo.schedule),
      MapEntry('Instructor', portfolioInfo.instructorName),
      MapEntry('Course', portfolioInfo.course),
      MapEntry('Course Code', portfolioInfo.courseCode),
      MapEntry('Semester & Academic Year', portfolioInfo.semesterAndYear),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Student Information',
          style: AppTextStyles.sectionHeader.copyWith(
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 12),
        ...fields.map((f) => _InfoRow(label: f.key, value: f.value)),
      ],
    );
  }

  // ── Sections included table ───────────────────────────────────────────
  Widget _buildSectionsIncluded() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sections Included',
          style: AppTextStyles.sectionHeader.copyWith(
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            children: List.generate(sections.length, (index) {
              final section = sections[index];
              final isLast = index == sections.length - 1;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: index.isEven
                      ? Colors.white
                      : AppColors.background.withValues(alpha: 0.5),
                  border: isLast
                      ? null
                      : const Border(
                          bottom: BorderSide(color: AppColors.divider),
                        ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        section.name,
                        style: AppTextStyles.bodyMedium,
                      ),
                    ),
                    Text(
                      '${section.count}',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  // ── Footer note ───────────────────────────────────────────────────────
  Widget _buildFooterNote() {
    return Column(
      children: [
        _buildDivider(),
        const SizedBox(height: 14),
        Text(
          'This portfolio was generated automatically from the '
          'student\u2019s uploaded academic records.',
          textAlign: TextAlign.center,
          style: AppTextStyles.labelSmall.copyWith(
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

// ─── Student info row ─────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final displayValue = value.trim().isEmpty ? '\u2014' : value;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 148,
            child: Text(
              label,
              style: AppTextStyles.labelMedium,
            ),
          ),
          Expanded(
            child: Text(
              displayValue,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}