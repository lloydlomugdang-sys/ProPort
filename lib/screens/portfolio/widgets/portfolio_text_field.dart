// LOCATION: lib/screens/portfolio/widgets/portfolio_text_field.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../constants/app_colors.dart';

/// Labelled text input field used throughout the Portfolio Information screen.
/// Matches wireframe: label above + white rounded input with placeholder.
/// Shows a red asterisk (*) when [required] is true.
class PortfolioTextField extends StatefulWidget {
  const PortfolioTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.required = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool required;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final int maxLines;

  @override
  State<PortfolioTextField> createState() => _PortfolioTextFieldState();
}

class _PortfolioTextFieldState extends State<PortfolioTextField>
    with SingleTickerProviderStateMixin {
  late final FocusNode _focusNode;
  late final AnimationController _borderCtrl;
  late final Animation<Color?> _borderColor;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _borderCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _borderColor = ColorTween(
      begin: AppColors.cardBorder,
      end: AppColors.primary,
    ).animate(CurvedAnimation(
      parent: _borderCtrl,
      curve: Curves.easeOut,
    ));
    _focusNode.addListener(_onFocus);
  }

  void _onFocus() {
    setState(() => _isFocused = _focusNode.hasFocus);
    _focusNode.hasFocus ? _borderCtrl.forward() : _borderCtrl.reverse();
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    _focusNode.dispose();
    _borderCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label row
        Row(
          children: [
            Text(
              widget.label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            if (widget.required)
              Text(
                '*',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.danger,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),

        // Input field
        AnimatedBuilder(
          animation: _borderCtrl,
          builder: (_, _) => Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _borderColor.value ?? AppColors.cardBorder,
                width: _isFocused ? 1.8 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: _isFocused
                      ? AppColors.primary.withValues(alpha: 0.10)
                      : Colors.black.withValues(alpha: 0.03),
                  blurRadius: _isFocused ? 10 : 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              onSubmitted: widget.onSubmitted,
              maxLines: widget.maxLines,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: GoogleFonts.poppins(
                  fontSize: 14,
                  color: AppColors.textMuted,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
        ),
      ],
    );
  }
}