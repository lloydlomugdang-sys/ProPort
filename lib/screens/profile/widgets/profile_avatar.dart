// LOCATION: lib/screens/profile/widgets/profile_avatar.dart

import 'dart:io';
import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';

/// Large circular profile avatar.
/// Shows a default icon when [avatarPath] is null.
/// Shows an edit badge overlay when [showEditBadge] is true.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    this.avatarPath,
    this.onTap,
    this.showEditBadge = false,
    this.size = 110,
  });

  final String? avatarPath;
  final VoidCallback? onTap;
  final bool showEditBadge;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          // Avatar circle
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.30),
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.20),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipOval(
              child: avatarPath != null
                  ? Image.file(
                      File(avatarPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _defaultIcon(),
                    )
                  : _defaultIcon(),
            ),
          ),

          // Edit badge
          if (showEditBadge)
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.secondary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  Widget _defaultIcon() {
    return Icon(
      Icons.person_rounded,
      size: size * 0.55,
      color: Colors.white,
    );
  }
}