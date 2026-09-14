// LOCATION: lib/screens/auth/widgets/auth_text_field.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../constants/app_colors.dart';

/// Plain text field matching the GradPort wireframe exactly.
/// Fill color matches the screen background (per wireframe), not white.
/// Height: ~34px via isDense + tight contentPadding.
/// No border, no shadow — just a flat rounded rectangle.
///
/// Set [showVisibilityToggle] to true on a password field to add a small
/// eye icon that toggles obscured/visible text without changing the
/// field's height, padding, or overall layout.
class AuthTextField extends StatefulWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    this.obscureText = false,
    this.showVisibilityToggle = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.autofillHints,
  });

  final TextEditingController controller;
  final bool obscureText;
  final bool showVisibilityToggle;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  late bool _obscured = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.showVisibilityToggle ? 48 : 34,
      decoration: BoxDecoration(
        color: AppColors.authFieldFill,
        borderRadius: BorderRadius.circular(4),
      ),
      child: TextField(
        controller: widget.controller,
        obscureText: widget.showVisibilityToggle
            ? _obscured
            : widget.obscureText,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        onSubmitted: widget.onSubmitted,
        autofillHints: widget.autofillHints,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: const Color(0xFF1A2E35),
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 48,
            minHeight: 48,
          ),
          suffixIcon: widget.showVisibilityToggle
              ? IconButton(
                  tooltip: _obscured ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscured = !_obscured),
                  icon: Icon(
                    _obscured
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: AppColors.authHint,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
