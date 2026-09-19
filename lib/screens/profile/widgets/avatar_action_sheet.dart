// LOCATION: lib/screens/profile/widgets/avatar_action_sheet.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../constants/app_colors.dart';
import '../../../services/auth_service.dart';
import '../../auth/widgets/auth_form_feedback.dart';

const int maxAvatarBytes = 5 * 1024 * 1024; // 5 MB

Future<void> showAvatarActionSheet({
  required BuildContext context,
  required AuthService authService,
  required void Function(bool isLoading) onLoadingChanged,
  required void Function(String message, {bool isError}) onFeedback,
  ImagePicker? imagePicker,
}) async {
  final picker = imagePicker ?? ImagePicker();
  final hasExistingAvatar =
      authService.user?.hasAvatar == true || authService.avatarBytes != null;

  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'Profile Photo',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(
                Icons.camera_alt_outlined,
                color: AppColors.primary,
              ),
              title: Text(
                'Take Photo',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () => Navigator.pop(sheetContext, 'camera'),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: AppColors.primary,
              ),
              title: Text(
                'Choose from Gallery',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () => Navigator.pop(sheetContext, 'gallery'),
            ),
            if (hasExistingAvatar)
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red.shade600,
                ),
                title: Text(
                  'Remove Photo',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.red.shade600,
                  ),
                ),
                onTap: () => Navigator.pop(sheetContext, 'remove'),
              ),
            ListTile(
              leading: const Icon(Icons.close_rounded, color: Colors.grey),
              title: Text(
                'Cancel',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
              ),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    ),
  );

  if (action == null || !context.mounted) return;

  if (action == 'remove') {
    onLoadingChanged(true);
    try {
      await authService.deleteAvatar();
      if (context.mounted) {
        onFeedback('Profile picture removed.');
      }
    } catch (error) {
      if (context.mounted) {
        onFeedback(authFormError(error), isError: true);
      }
    } finally {
      onLoadingChanged(false);
    }
    return;
  }

  final source = action == 'camera' ? ImageSource.camera : ImageSource.gallery;

  try {
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !context.mounted) return;

    final length = await picked.length();
    if (length > maxAvatarBytes) {
      onFeedback('Image must be under 5MB.', isError: true);
      return;
    }

    final bytes = await picked.readAsBytes();
    final ext = picked.name.split('.').last.toLowerCase();
    final mimeType = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'jpg' || 'jpeg' => 'image/jpeg',
      _ => null,
    };
    if (mimeType == null) {
      onFeedback(
        'Please select a JPG, JPEG, PNG, or WebP image.',
        isError: true,
      );
      return;
    }

    onLoadingChanged(true);
    try {
      await authService.updateAvatar(
        bytes: bytes,
        filename: picked.name,
        mimeType: mimeType,
      );
      if (context.mounted) {
        onFeedback('Profile picture updated.');
      }
    } catch (error) {
      if (context.mounted) {
        onFeedback(authFormError(error), isError: true);
      }
    } finally {
      onLoadingChanged(false);
    }
  } catch (error) {
    if (context.mounted) {
      final errorStr = error.toString().toLowerCase();
      final message =
          errorStr.contains('permission') || errorStr.contains('denied')
          ? 'Permission was denied. Please allow camera or photo access in device settings.'
          : authFormError(error);
      onFeedback(message, isError: true);
    }
  }
}

