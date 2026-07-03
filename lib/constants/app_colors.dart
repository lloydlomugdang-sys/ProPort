// LOCATION: lib/constants/app_colors.dart
// REPLACE the existing file entirely.

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ─── Brand palette ────────────────────────────────────────────────────────
  static const Color primary    = Color(0xFF166088);
  static const Color secondary  = Color(0xFF4A6FA5);
  static const Color neutral    = Color(0xFF4F6D7A);
  static const Color surface    = Color(0xFFC0D6DF);
  static const Color background = Color(0xFFDBE9EE);

  // ─── Text ─────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF1A2E35);
  static const Color textSecondary = Color(0xFF4F6D7A);
  static const Color textMuted     = Color(0xFF8FAAB5);
  static const Color textOnPrimary = Colors.white;

  // ─── Basics (kept for backward compat with any remaining references) ──────
  static const Color white = Colors.white;
  static const Color black = Colors.black;

  // ─── UI surfaces ──────────────────────────────────────────────────────────
  static const Color cardBackground   = Colors.white;
  static const Color cardBorder       = Color(0xFFD0E3EA);
  static const Color divider          = Color(0xFFDCEBF0);
  static const Color inputFill        = Colors.white;
  static const Color inputBorder      = Color(0xFFCFDFE6);
  static const Color inputBorderFocus = Color(0xFF166088);

  // ─── Status chips ─────────────────────────────────────────────────────────
  static const Color statusNoneBg        = Color(0xFFE8F0F3);
  static const Color statusNoneText      = Color(0xFF8FAAB5);
  static const Color statusCompleteBg    = Color(0xFFDFF2E9);
  static const Color statusCompleteText  = Color(0xFF27AE60);
  static const Color statusIncompleteBg  = Color(0xFFFFF3DC);
  static const Color statusIncompleteText = Color(0xFFF39C12);

  // ─── Semantic ─────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF27AE60);
  static const Color warning = Color(0xFFF39C12);
  static const Color danger  = Color(0xFFE74C3C);

  // ─── File type ────────────────────────────────────────────────────────────
  static const Color filePdf   = Color(0xFFE74C3C);
  static const Color fileImage = Color(0xFF3498DB);
  static const Color fileDoc   = Color(0xFF2980B9);
  static const Color fileOther = Color(0xFF8E44AD);

  // ─── Bottom nav ───────────────────────────────────────────────────────────
  static const Color navBackground = Color(0xFF166088);
  static const Color navSelected   = Colors.white;
  static const Color navUnselected = Color(0xFF9DC4D8);

  // ─── Header ───────────────────────────────────────────────────────────────
  static const Color headerBackground = Color(0xFF166088);
  static const Color headerText       = Colors.white;

  // ─── Gradient ─────────────────────────────────────────────────────────────
  static const List<Color> primaryGradient = [
    Color(0xFF166088),
    Color(0xFF4A6FA5),
  ];

  // ─── Auth module ──────────────────────────────────────────────────────────
  static const Color authPrimary            = Color(0xFF166088);
  static const Color authSecondary          = Color(0xFF4A6FA5);
  static const Color authNeutral            = Color(0xFF4F6D7A);
  static const Color authSurface            = Color(0xFFC0D6DF);
  static const Color authBackground         = Color(0xFFDBE9EE);
  static const Color authFieldFill          = Colors.white;
  static const Color authFieldBorder        = Color(0xFFCFDFE6);
  static const Color authFieldBorderFocused = Color(0xFF166088);
  static const Color authHint               = Color(0xFF9DB5BF);
  static const Color authDivider            = Color(0xFFB8CED6);
  static const Color strengthWeak           = Color(0xFFE74C3C);
  static const Color strengthMedium         = Color(0xFFF39C12);
  static const Color strengthStrong         = Color(0xFF27AE60);
  static const Color matchSuccess           = Color(0xFF27AE60);
  static const Color matchError             = Color(0xFFE74C3C);
  static const List<Color> authButtonGradient = [
    Color(0xFF166088),
    Color(0xFF4A6FA5),
  ];
}