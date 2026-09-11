// LOCATION: lib/screens/files/widgets/upload_card.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../constants/app_colors.dart';

/// Upload card matching the wireframe.
/// States:
///   [idle]    — teal upload icon, "Tap to upload file", "PDF, JPG, PNG"
///   [picked]  — file name + type icon + success indicator
class UploadCard extends StatelessWidget {
  const UploadCard({
    super.key,
    required this.onTap,
    this.fileName,
    this.filePath,
  });

  final VoidCallback onTap;
  final String? fileName;
  final String? filePath;

  bool get _hasPicked => fileName != null;

  IconData get _fileIcon {
    if (fileName == null) return Icons.upload_file_rounded;
    final lower = fileName!.toLowerCase();
    if (lower.endsWith('.pdf')) {
      return Icons.picture_as_pdf_rounded;
    }
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png')) {
      return Icons.image_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  Color get _fileIconColor {
    if (fileName == null) return AppColors.primary;
    final lower = fileName!.toLowerCase();
    if (lower.endsWith('.pdf')) {
      return AppColors.filePdf;
    }
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png')) {
      return AppColors.fileImage;
    }
    return AppColors.fileOther;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: _hasPicked
              ? AppColors.primary.withValues(alpha: 0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hasPicked ? AppColors.primary : AppColors.cardBorder,
            width: _hasPicked ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: _hasPicked ? _pickedState() : _idleState(),
      ),
    );
  }

  Widget _idleState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.upload_file_rounded,
            color: AppColors.primary,
            size: 30,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Tap to upload file',
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'PDF, JPG, PNG',
          style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _pickedState() {
    return Row(
      children: [
        // File icon
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _fileIconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_fileIcon, color: _fileIconColor, size: 24),
        ),
        const SizedBox(width: 12),

        // File name
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fileName!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Tap to change file',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),

        // Success badge
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: AppColors.success,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, size: 16, color: Colors.white),
        ),
      ],
    );
  }
}
