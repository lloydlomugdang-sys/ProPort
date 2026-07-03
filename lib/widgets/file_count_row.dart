// LOCATION: lib/widgets/file_count_row.dart

import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

class FileCountRow extends StatelessWidget {
  const FileCountRow({
    super.key,
    required this.label,
    required this.count,
    this.onTap,
  });

  final String label;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textPrimary),
              ),
            ),
            Text(
              count.toString(),
              style: AppTextStyles.labelLarge
                  .copyWith(color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}