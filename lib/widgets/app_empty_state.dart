import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

/// Modern, approachable empty state widget inspired by GradPort's design system.
/// Communicates Context (why empty), Direction (what to do next), and Action (prominent CTA).
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
    this.actionIcon = Icons.add_rounded,
    this.illustration,
    this.icon,
    this.footnote,
    this.isCompact = false,
  });

  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;
  final Widget? illustration;
  final IconData? icon;
  final String? footnote;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    if (isCompact) {
      return _buildCompact(context);
    }

    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Illustration / Icon
            illustration ?? _buildDefaultIllustration(context),
            const SizedBox(height: 24),

            // Context: Title
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),

            // Direction: Description
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                description,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
            ),

            // Action: Primary CTA Button
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 22),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: actionIcon != null
                    ? Icon(actionIcon, size: 18)
                    : const SizedBox.shrink(),
                label: Text(
                  actionLabel!,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  shadowColor: Colors.transparent,
                ),
              ),
            ],

            // Footnote
            if (footnote != null) ...[
              const SizedBox(height: 16),
              Text(
                footnote!,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder.withValues(alpha: 0.6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon ?? Icons.folder_open_rounded,
            size: 28,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 6),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              description,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                actionLabel!,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDefaultIllustration(BuildContext context) {
    if (icon != null) {
      return Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: const Color(0xFFEBF3F8),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(
            icon,
            size: 46,
            color: AppColors.primary,
          ),
        ),
      );
    }

    return const AppEmptyIllustration();
  }
}

/// Stylized Flutter vector graphic showing a soft cloud backdrop,
/// folder with a document, and friendly accent sparkles.
class AppEmptyIllustration extends StatelessWidget {
  const AppEmptyIllustration({
    super.key,
    this.size = 140,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _FolderCloudPainter(),
      ),
    );
  }
}

class _FolderCloudPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // 1. Soft cloud background shape (pastel blue)
    final cloudPaint = Paint()
      ..color = const Color(0xFFEBF4FA)
      ..style = PaintingStyle.fill;

    // Draw clustered circles to form a soft friendly cloud
    canvas.drawCircle(Offset(center.dx - 22, center.dy + 4), size.width * 0.32, cloudPaint);
    canvas.drawCircle(Offset(center.dx + 22, center.dy + 8), size.width * 0.28, cloudPaint);
    canvas.drawCircle(Offset(center.dx, center.dy - 16), size.width * 0.30, cloudPaint);

    // 2. Playful sparkle / dash accents
    final accentPaint = Paint()
      ..color = const Color(0xFF4A90E2).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    // Left sparkle rays
    canvas.drawLine(
      Offset(center.dx - size.width * 0.38, center.dy - size.height * 0.16),
      Offset(center.dx - size.width * 0.32, center.dy - size.height * 0.13),
      accentPaint,
    );
    canvas.drawLine(
      Offset(center.dx - size.width * 0.37, center.dy - size.height * 0.04),
      Offset(center.dx - size.width * 0.31, center.dy - size.height * 0.05),
      accentPaint,
    );

    // Right sparkle rays
    canvas.drawLine(
      Offset(center.dx + size.width * 0.34, center.dy - size.height * 0.18),
      Offset(center.dx + size.width * 0.40, center.dy - size.height * 0.15),
      accentPaint,
    );
    canvas.drawLine(
      Offset(center.dx + size.width * 0.36, center.dy - size.height * 0.06),
      Offset(center.dx + size.width * 0.42, center.dy - size.height * 0.08),
      accentPaint,
    );

    // 3. Document sticking out of folder (White rounded sheet with text lines)
    final docRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy - 4),
      width: size.width * 0.46,
      height: size.height * 0.46,
    );

    final docShadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(docRect.shift(const Offset(0, 2)), const Radius.circular(8)),
      docShadowPaint,
    );

    final docPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(docRect, const Radius.circular(8)),
      docPaint,
    );

    final docBorderPaint = Paint()
      ..color = const Color(0xFFD6E3EC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawRRect(
      RRect.fromRectAndRadius(docRect, const Radius.circular(8)),
      docBorderPaint,
    );

    // Document text line placeholders
    final docLinePaint = Paint()
      ..color = const Color(0xFFC7D7E2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final docTop = docRect.top + 14;
    canvas.drawLine(
      Offset(docRect.left + 12, docTop),
      Offset(docRect.right - 18, docTop),
      docLinePaint,
    );
    canvas.drawLine(
      Offset(docRect.left + 12, docTop + 9),
      Offset(docRect.right - 12, docTop + 9),
      docLinePaint,
    );
    canvas.drawLine(
      Offset(docRect.left + 12, docTop + 18),
      Offset(docRect.left + 28, docTop + 18),
      docLinePaint,
    );

    // 4. Folder back tab (slightly darker blue)
    final folderBackTab = Path()
      ..moveTo(center.dx - size.width * 0.32, center.dy - 10)
      ..lineTo(center.dx - size.width * 0.12, center.dy - 10)
      ..lineTo(center.dx - size.width * 0.05, center.dy + 4)
      ..lineTo(center.dx - size.width * 0.32, center.dy + 4)
      ..close();
    canvas.drawPath(
      folderBackTab,
      Paint()..color = const Color(0xFF3B82F6),
    );

    // 5. Main Folder Front Body (rich vibrant blue with soft gradient look)
    final folderRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy + 18),
      width: size.width * 0.68,
      height: size.height * 0.44,
    );

    final folderShadow = Paint()
      ..color = const Color(0xFF1E3A8A).withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(folderRect.shift(const Offset(0, 4)), const Radius.circular(14)),
      folderShadow,
    );

    final folderPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF5B9BF3),
          Color(0xFF3B82F6),
        ],
      ).createShader(folderRect)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(folderRect, const Radius.circular(14)),
      folderPaint,
    );

    // Subtle gloss highlight on folder top edge
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final highlightPath = Path()
      ..moveTo(folderRect.left + 14, folderRect.top + 1.2)
      ..lineTo(folderRect.right - 14, folderRect.top + 1.2);
    canvas.drawPath(highlightPath, highlightPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

