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
    this.backgroundColor,
    this.foregroundColor,
  });

  final String title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool centerTitle;
  final PreferredSizeWidget? bottom;
  final double elevation;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? Colors.white;
    final fg = foregroundColor ?? AppColors.textPrimary;
    return AppBar(
      backgroundColor: bg,
      foregroundColor: fg,
      elevation: elevation,
      scrolledUnderElevation: 0,
      centerTitle: centerTitle,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      title: Text(
        title,
        style: AppTextStyles.h2.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
      leading: leading,
      automaticallyImplyLeading: false,
      actions: actions,
      bottom: bottom ??
          PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(
              color: AppColors.cardBorder.withValues(alpha: 0.5),
              height: 0.8,
            ),
          ),
    );
  }
}

class GradBackAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GradBackAppBar({
    super.key,
    required this.title,
    this.actions,
    this.onBack,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String title;
  final List<Widget>? actions;
  final VoidCallback? onBack;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? Colors.white;
    final fg = foregroundColor ?? AppColors.textPrimary;
    return AppBar(
      backgroundColor: bg,
      foregroundColor: fg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      title: Text(
        title,
        style: AppTextStyles.h2.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
      leading: IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
        color: fg,
        onPressed: onBack ?? () => Navigator.of(context).pop(),
      ),
      actions: actions,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          color: AppColors.cardBorder.withValues(alpha: 0.5),
          height: 0.8,
        ),
      ),
    );
  }
}
