import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';

Future<String?> showSavePortfolioDialog({
  required BuildContext context,
  required String initialTitle,
}) {
  final controller = TextEditingController(
    text: initialTitle == 'Untitled Portfolio' ? '' : initialTitle,
  );

  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Save Portfolio',
          style: TextStyle(
            color: AppColors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(
            color: AppColors.black,
          ),
          decoration: InputDecoration(
            hintText: 'Enter portfolio title',
            hintStyle: const TextStyle(
              color: Colors.grey,
            ),
            filled: true,
            fillColor: AppColors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              controller.dispose();
              Navigator.pop(dialogContext);
            },
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final title = controller.text.trim();

              if (title.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Portfolio title cannot be empty.'),
                  ),
                );
                return;
              }

              controller.dispose();
              Navigator.pop(dialogContext, title);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.input,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
}