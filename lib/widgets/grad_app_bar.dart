// LOCATION: lib/widgets/grad_app_bar.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

class GradAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GradAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.centerTitle = true,
    this.bottom,
    this.elevation = 0,
  });

  final String title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool centerTitle;
  final PreferredSizeWidget? bottom;
  final double elevation;

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.headerBackground,
      foregroundColor: AppColors.headerText,
      elevation: elevation,
      centerTitle: centerTitle,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      title: Text(title, style: AppTextStyles.appBarTitle),
      leading: leading,
      actions: actions,
      bottom: bottom,
    );
  }
}

class GradBackAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GradBackAppBar({
    super.key,
    required this.title,
    this.actions,
    this.onBack,
  });

  final String title;
  final List<Widget>? actions;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.headerBackground,
      foregroundColor: AppColors.headerText,
      elevation: 0,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      title: Text(title, style: AppTextStyles.appBarTitle),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        color: AppColors.headerText,
        onPressed: onBack ?? () => Navigator.of(context).pop(),
      ),
      actions: actions,
    );
  }
}