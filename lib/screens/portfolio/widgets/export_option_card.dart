// LOCATION: lib/screens/portfolio/widgets/export_option_card.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../constants/app_colors.dart';
import '../models/portfolio_models.dart';

/// Selectable export format card (PDF / DOCX).
/// Matches wireframe: white card, icon, label, subtitle.
/// Shows a blue checkmark badge in top-right corner when selected.
class ExportOptionCard extends StatelessWidget {
  const ExportOptionCard({
    super.key,
    required this.format,
    required this.isSelected,
    required this.onTap,
  });

  final ExportFormat format;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.cardBorder,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: isSelected ? 10 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Content
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // File icon
                _buildIcon(),
                const SizedBox(height: 10),

                // Label
                Text(
                  format.label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),

                // Subtitle
                Text(
                  format.subtitle,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),

            // Checkmark badge — top right, visible only when selected
            if (isSelected)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon() {
    switch (format) {
      case ExportFormat.pdf:
        return Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFFFFEBEE),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.picture_as_pdf_rounded,
            color: Color(0xFFE53935),
            size: 32,
          ),
        );
      case ExportFormat.docx:
        return Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFFE3F2FD),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.article_rounded,
            color: Color(0xFF1565C0),
            size: 32,
          ),
        );
    }
  }
}