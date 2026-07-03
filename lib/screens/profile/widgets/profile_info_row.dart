// LOCATION: lib/screens/profile/widgets/profile_info_row.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../constants/app_colors.dart';

/// Read-only profile info row — icon + value, used in ProfileScreen.
class ProfileInfoRow extends StatelessWidget {
  const ProfileInfoRow({
    super.key,
    required this.icon,
    required this.value,
    this.isLast = false,
  });

  final IconData icon;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AppColors.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textPrimary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          const Divider(height: 1, indent: 16, endIndent: 16,
              color: AppColors.divider),
      ],
    );
  }
}

/// Editable profile info row — same layout but with a pencil icon on the right.
/// Used in EditProfileScreen. Tapping the row or pencil opens an edit dialog.
class EditableInfoRow extends StatelessWidget {
  const EditableInfoRow({
    super.key,
    required this.icon,
    required this.value,
    required this.onEdit,
    this.isLast = false,
  });

  final IconData icon;
  final String value;
  final VoidCallback onEdit;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, size: 22, color: AppColors.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    value,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
                const Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
        if (!isLast)
          const Divider(height: 1, indent: 16, endIndent: 16,
              color: AppColors.divider),
      ],
    );
  }
}