import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';

Future<String?> showAlignmentDialog(
  BuildContext context,
) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 36),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Align Element',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 16),

              _AlignmentOption(
                icon: Icons.align_horizontal_left,
                label: 'Align Left',
                value: 'left',
                dialogContext: dialogContext,
              ),

              _AlignmentOption(
                icon: Icons.align_horizontal_center,
                label: 'Center Horizontally',
                value: 'centerHorizontal',
                dialogContext: dialogContext,
              ),

              _AlignmentOption(
                icon: Icons.align_horizontal_right,
                label: 'Align Right',
                value: 'right',
                dialogContext: dialogContext,
              ),

              _AlignmentOption(
                icon: Icons.align_vertical_top,
                label: 'Align Top',
                value: 'top',
                dialogContext: dialogContext,
              ),

              _AlignmentOption(
                icon: Icons.align_vertical_center,
                label: 'Center Vertically',
                value: 'centerVertical',
                dialogContext: dialogContext,
              ),

              _AlignmentOption(
                icon: Icons.align_vertical_bottom,
                label: 'Align Bottom',
                value: 'bottom',
                dialogContext: dialogContext,
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _AlignmentOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final BuildContext dialogContext;

  const _AlignmentOption({
    required this.icon,
    required this.label,
    required this.value,
    required this.dialogContext,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.pop(dialogContext, value);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: AppColors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}