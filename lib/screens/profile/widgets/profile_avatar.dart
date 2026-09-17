// LOCATION: lib/screens/profile/widgets/profile_avatar.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';

/// Large circular profile avatar.
/// Renders [avatarBytes] (in-memory image from API) or [avatarPath] (local file).
/// Falls back to [initials] if provided, or a default person icon.
/// Shows an edit badge overlay when [showEditBadge] is true.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    this.avatarBytes,
    this.avatarPath,
    this.initials,
    this.onTap,
    this.showEditBadge = false,
    this.isLoading = false,
    this.size = 110,
  });

  final Uint8List? avatarBytes;
  final String? avatarPath;
  final String? initials;
  final VoidCallback? onTap;
  final bool showEditBadge;
  final bool isLoading;
  final double size;

  @override
  Widget build(BuildContext context) {
    final badgeSize = (size * 0.3).clamp(20.0, 32.0);

    return GestureDetector(
      onTap: isLoading ? null : onTap,
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
                width: size > 60 ? 3 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.20),
                  blurRadius: size > 60 ? 16 : 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipOval(
              child: isLoading
                  ? Center(
                      child: SizedBox(
                        width: size * 0.35,
                        height: size * 0.35,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : _buildContent(),
            ),
          ),

          // Edit badge
          if (showEditBadge && !isLoading)
            Container(
              width: badgeSize,
              height: badgeSize,
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
              child: Icon(
                Icons.camera_alt_rounded,
                size: badgeSize * 0.5,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (avatarBytes != null && avatarBytes!.isNotEmpty) {
      return Image.memory(
        avatarBytes!,
        fit: BoxFit.cover,
        width: size,
        height: size,
        errorBuilder: (context, error, stackTrace) => _defaultOrInitials(),
      );
    }
    if (avatarPath != null && avatarPath!.isNotEmpty) {
      return Image.file(
        File(avatarPath!),
        fit: BoxFit.cover,
        width: size,
        height: size,
        errorBuilder: (context, error, stackTrace) => _defaultOrInitials(),
      );
    }
    return _defaultOrInitials();
  }

  Widget _defaultOrInitials() {
    final trimmed = initials?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      return Center(
        child: Text(
          trimmed,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.36,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      );
    }
    return _defaultIcon();
  }

  Widget _defaultIcon() {
    return Icon(Icons.person_rounded, size: size * 0.55, color: Colors.white);
  }
}
