import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';

class FontStyleOption {
  final String label;
  final String fontFamily;

  const FontStyleOption({
    required this.label,
    required this.fontFamily,
  });
}

const List<FontStyleOption> portfolioFontStyles = [
  FontStyleOption(
    label: 'Sans Serif',
    fontFamily: 'sans-serif',
  ),
  FontStyleOption(
    label: 'Serif',
    fontFamily: 'serif',
  ),
  FontStyleOption(
    label: 'Monospace',
    fontFamily: 'monospace',
  ),
  FontStyleOption(
    label: 'Cursive',
    fontFamily: 'cursive',
  ),
];

Future<String?> showFontStyleDialog({
  required BuildContext context,
  required String currentFontFamily,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 34),
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
                'Choose Font Style',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 16),

              ...portfolioFontStyles.map((option) {
                final bool isSelected =
                    option.fontFamily == currentFontFamily;

                return InkWell(
                  onTap: () {
                    Navigator.pop(dialogContext, option.fontFamily);
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.input
                          : AppColors.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.white
                            : AppColors.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            option.label,
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              fontFamily: option.fontFamily,
                            ),
                          ),
                        ),
                        if (isSelected)
                          const Icon(
                            Icons.check_circle,
                            color: AppColors.white,
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 4),

              SizedBox(
                width: double.infinity,
                height: 42,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}