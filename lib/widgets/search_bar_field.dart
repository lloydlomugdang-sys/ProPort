// LOCATION: lib/widgets/search_bar_field.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

class SearchBarField extends StatelessWidget {
  const SearchBarField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hintText = 'Search...',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFFE6EEF3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: GoogleFonts.poppins(
          fontSize: 13,
          color: AppColors.textPrimary,
        ),
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,

          hintText: hintText,

          hintStyle: GoogleFonts.poppins(
            fontSize: 13,
            color: AppColors.textMuted,
          ),

          prefixIcon: const Icon(
            Icons.search,
            size: 19,
            color: Color(0xFF3A4A5A),
          ),

          prefixIconConstraints: const BoxConstraints(
            minWidth: 42,
            minHeight: 42,
          ),

          contentPadding: const EdgeInsets.only(
            top: 9,
            bottom: 9,
            right: 12,
          ),
        ),
      ),
    );
  }
}