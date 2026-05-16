import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';
import '../models/portfolio_shape_element.dart';

Future<PortfolioShapeType?> showShapePickerDialog(
  BuildContext context,
) {
  return showDialog<PortfolioShapeType>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
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
                'Choose Shape',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 18),

              _ShapeOption(
                title: 'Rectangle',
                icon: Icons.crop_16_9_outlined,
                onTap: () {
                  Navigator.pop(
                    dialogContext,
                    PortfolioShapeType.rectangle,
                  );
                },
              ),

              _ShapeOption(
                title: 'Circle',
                icon: Icons.circle_outlined,
                onTap: () {
                  Navigator.pop(
                    dialogContext,
                    PortfolioShapeType.circle,
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ShapeOption extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _ShapeOption({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: AppColors.white,
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}