import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';

enum ElementOptionAction {
  copy,
  paste,
  duplicate,
  delete,
  bringToFront,
  sendToBack,
  alignment,
}

Future<ElementOptionAction?> showElementOptionsDialog(
  BuildContext context,
) {
  return showDialog<ElementOptionAction>(
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
                'Element Options',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 16),

              _ElementOptionItem(
                icon: Icons.content_copy_outlined,
                label: 'Copy',
                action: ElementOptionAction.copy,
                dialogContext: dialogContext,
              ),

              _ElementOptionItem(
                icon: Icons.content_paste_outlined,
                label: 'Paste',
                action: ElementOptionAction.paste,
                dialogContext: dialogContext,
              ),

              _ElementOptionItem(
                icon: Icons.copy_all_outlined,
                label: 'Duplicate',
                action: ElementOptionAction.duplicate,
                dialogContext: dialogContext,
              ),

              _ElementOptionItem(
                icon: Icons.delete_outline,
                label: 'Delete',
                action: ElementOptionAction.delete,
                dialogContext: dialogContext,
                isDanger: true,
              ),

              _ElementOptionItem(
                icon: Icons.flip_to_front_outlined,
                label: 'Bring to Front',
                action: ElementOptionAction.bringToFront,
                dialogContext: dialogContext,
              ),

              _ElementOptionItem(
                icon: Icons.flip_to_back_outlined,
                label: 'Send to Back',
                action: ElementOptionAction.sendToBack,
                dialogContext: dialogContext,
              ),

              _ElementOptionItem(
                icon: Icons.format_align_center,
                label: 'Alignment',
                action: ElementOptionAction.alignment,
                dialogContext: dialogContext,
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ElementOptionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final ElementOptionAction action;
  final BuildContext dialogContext;
  final bool isDanger;

  const _ElementOptionItem({
    required this.icon,
    required this.label,
    required this.action,
    required this.dialogContext,
    this.isDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.pop(dialogContext, action);
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
              color: isDanger ? AppColors.danger : AppColors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: isDanger ? AppColors.danger : AppColors.white,
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