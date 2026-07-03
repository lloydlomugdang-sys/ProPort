import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../constants/app_colors.dart';

enum PasswordStrength { none, weak, medium, strong }

PasswordStrength evaluatePasswordStrength(String password) {
  if (password.isEmpty) return PasswordStrength.none;
  int score = 0;
  if (password.length >= 8) score++;
  if (password.length >= 12) score++;
  if (RegExp(r'[A-Z]').hasMatch(password)) score++;
  if (RegExp(r'[0-9]').hasMatch(password)) score++;
  if (RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(password)) score++;
  if (score <= 1) return PasswordStrength.weak;
  if (score <= 3) return PasswordStrength.medium;
  return PasswordStrength.strong;
}

/// Animated 3-segment password strength bar.
/// Designed for the dark teal auth card — inactive segments use white24.
class PasswordStrengthIndicator extends StatelessWidget {
  const PasswordStrengthIndicator({super.key, required this.password});
  final String password;

  @override
  Widget build(BuildContext context) {
    final strength = evaluatePasswordStrength(password);
    if (strength == PasswordStrength.none) return const SizedBox.shrink();

    final int filled = switch (strength) {
      PasswordStrength.none   => 0,
      PasswordStrength.weak   => 1,
      PasswordStrength.medium => 2,
      PasswordStrength.strong => 3,
    };
    final Color active = switch (strength) {
      PasswordStrength.none   => Colors.transparent,
      PasswordStrength.weak   => AppColors.strengthWeak,
      PasswordStrength.medium => AppColors.strengthMedium,
      PasswordStrength.strong => AppColors.strengthStrong,
    };
    final String label = switch (strength) {
      PasswordStrength.none   => '',
      PasswordStrength.weak   => 'Weak',
      PasswordStrength.medium => 'Medium',
      PasswordStrength.strong => 'Strong',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: List.generate(3, (i) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < 2 ? 4 : 0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  height: 4,
                  decoration: BoxDecoration(
                    color: i < filled ? active : Colors.white24,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 5),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Align(
            key: ValueKey(label),
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: active,
              ),
            ),
          ),
        ),
      ],
    );
  }
}