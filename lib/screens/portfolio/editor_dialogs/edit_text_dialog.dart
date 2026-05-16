import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';

Future<String?> showEditTextDialog({
  required BuildContext context,
  required String initialText,
}) {
  final controller = TextEditingController(text: initialText);

  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text(
          'Edit Text',
          style: TextStyle(
            color: AppColors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(
            color: AppColors.black,
          ),
          decoration: InputDecoration(
            hintText: 'Enter text',
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
              final updatedText = controller.text.trim();

              if (updatedText.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Text cannot be empty.'),
                  ),
                );
                return;
              }

              controller.dispose();
              Navigator.pop(dialogContext, updatedText);
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