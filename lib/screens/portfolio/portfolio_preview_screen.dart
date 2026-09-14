// LOCATION: lib/screens/portfolio/portfolio_preview_screen.dart

import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/grad_app_bar.dart';
import '../../widgets/primary_button.dart';
import 'models/portfolio_models.dart';
import 'portfolio_list_screen.dart';

/// Read-only preview of saved portfolio information.
/// Styled to resemble the first page of an academic PDF document rather
/// than a Canva-style editor — this is a static, print-like preview.
///
/// Displays saved title-page information. Document export is not implemented.
class PortfolioPreviewScreen extends StatelessWidget {
  const PortfolioPreviewScreen({
    super.key,
    required this.portfolioInfo,
    PortfolioSummary? summary,
    this.exportFormat = ExportFormat.pdf,
  }) : summary = summary ?? const PortfolioSummary(sections: []);

  final PortfolioInfo portfolioInfo;
  final PortfolioSummary summary;

  /// Reserved for the legacy export screen; no export or download is performed.
  final ExportFormat exportFormat;

  // ─── Actions ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final sections = summary.sections.isNotEmpty
        ? summary.sections
        : PortfolioSummary.empty.sections;

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
        border: Border(top: BorderSide(color: AppColors.divider)),
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
                label: 'Back to My Portfolios',
                onPressed: () => PortfolioListScreen.returnToList(context),
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
  const _PreviewSheet({required this.portfolioInfo, required this.sections});

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
      MapEntry('Schedule', portfolioInfo.formattedSchedule),
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
          style: AppTextStyles.sectionHeader.copyWith(color: AppColors.primary),
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
          style: AppTextStyles.sectionHeader.copyWith(color: AppColors.primary),
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
          'Saved portfolio information. PDF/DOCX export is not available yet.',
          textAlign: TextAlign.center,
          style: AppTextStyles.labelSmall.copyWith(fontStyle: FontStyle.italic),
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
            child: Text(label, style: AppTextStyles.labelMedium),
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
