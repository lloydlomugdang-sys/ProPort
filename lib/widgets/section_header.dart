// LOCATION: lib/widgets/section_header.dart
// This file did NOT exist in the repo — create it here.

import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

/// Bold section header used throughout the app.
/// Examples: "Portfolio Tracker", "Uploaded Files"
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.color,
  });

  final String title;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTextStyles.h3.copyWith(
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Smaller category label used inside folder sections.
class CategoryLabel extends StatelessWidget {
  const CategoryLabel({
    super.key,
    required this.title,
    this.color,
  });

  final String title;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTextStyles.h4.copyWith(
        color: color ?? AppColors.primary,
      ),
    );
  }
}