import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_colors.dart';
import '../services/document_models.dart';

/// Polished file-type placeholder card for formats that cannot be rendered
/// visually as image or PDF rasters (e.g. DOC, DOCX, XLS, XLSX, PPT, PPTX).
///
/// Ensures every document in previews has a clear, attractive visual card
/// displaying format badge, filename, file size, and tap affordance.
class DocumentUnsupportedPreview extends StatelessWidget {
  const DocumentUnsupportedPreview({
    super.key,
    required this.document,
    this.onTap,
  });

  final DocumentRecord document;
  final VoidCallback? onTap;

  String get _extension {
    final dotIndex = document.originalFileName.lastIndexOf('.');
    if (dotIndex != -1 && dotIndex < document.originalFileName.length - 1) {
      return document.originalFileName.substring(dotIndex + 1).toUpperCase();
    }
    final rawExt = document.extension.replaceAll('.', '').trim();
    return rawExt.isNotEmpty ? rawExt.toUpperCase() : 'FILE';
  }

  _FileTypeDetails get _typeDetails {
    final ext = _extension.toLowerCase();
    switch (ext) {
      case 'doc':
      case 'docx':
        return const _FileTypeDetails(
          icon: Icons.description_rounded,
          color: Color(0xFF2B579A),
          label: 'Word Document',
        );
      case 'xls':
      case 'xlsx':
      case 'csv':
        return const _FileTypeDetails(
          icon: Icons.table_chart_rounded,
          color: Color(0xFF217346),
          label: 'Spreadsheet',
        );
      case 'ppt':
      case 'pptx':
        return const _FileTypeDetails(
          icon: Icons.slideshow_rounded,
          color: Color(0xFFD24726),
          label: 'Presentation',
        );
      case 'txt':
      case 'rtf':
      case 'md':
        return const _FileTypeDetails(
          icon: Icons.article_rounded,
          color: Color(0xFF4A5568),
          label: 'Text Document',
        );
      default:
        return const _FileTypeDetails(
          icon: Icons.insert_drive_file_rounded,
          color: AppColors.primary,
          label: 'Document',
        );
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final details = _typeDetails;
    final ext = _extension;
    final sizeText = _formatFileSize(document.sizeBytes);

    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // File kind icon badge
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: details.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  details.icon,
                  size: 32,
                  color: details.color,
                ),
              ),
              Positioned(
                bottom: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: details.color,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    ext,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // File Name
          Text(
            document.originalFileName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          // Metadata & size
          Text(
            '${details.label} • $sizeText',
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          // Interaction hint
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.visibility_outlined,
                  size: 13,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'Tap to view details',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: card,
        ),
      );
    }

    return card;
  }
}

class _FileTypeDetails {
  const _FileTypeDetails({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;
}
