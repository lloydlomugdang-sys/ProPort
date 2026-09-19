// LOCATION: lib/widgets/file_list_item.dart

import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

class FileListItem extends StatelessWidget {
  const FileListItem({
    super.key,
    required this.fileName,
    required this.fileType,
    required this.year,
    required this.onTap,
    this.onDelete,
    this.onRename,
  });

  final String fileName;
  final String fileType;
  final String year;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onRename;

  IconData get _icon {
    final l = fileName.toLowerCase();
    if (l.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (l.endsWith('.png') || l.endsWith('.jpg') || l.endsWith('.jpeg')) {
      return Icons.image_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  Color get _iconColor {
    final l = fileName.toLowerCase();
    if (l.endsWith('.pdf')) return AppColors.filePdf;
    if (l.endsWith('.png') || l.endsWith('.jpg') || l.endsWith('.jpeg')) {
      return AppColors.fileImage;
    }
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_icon, color: _iconColor, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelLarge,
                  ),
                  const SizedBox(height: 2),
                  Text('$fileType • $year',
                      style: AppTextStyles.labelSmall),
                ],
              ),
            ),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert,
                  color: AppColors.textMuted, size: 20),
              color: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              itemBuilder: (_) => [
                if (onRename != null)
                  PopupMenuItem(
                    value: 'rename',
                    child: Row(children: [
                      const Icon(Icons.edit_outlined,
                          size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text('Rename',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.textPrimary)),
                    ]),
                  ),
                if (onDelete != null)
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      const Icon(Icons.delete_outline,
                          size: 18, color: AppColors.danger),
                      const SizedBox(width: 8),
                      Text('Delete',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.danger)),
                    ]),
                  ),
              ],
              onSelected: (v) {
                if (v == 'delete') onDelete?.call();
                if (v == 'rename') onRename?.call();
              },
            ),
          ],
        ),
      ),
    );
  }
}