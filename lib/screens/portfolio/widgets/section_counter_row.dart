// LOCATION: lib/screens/portfolio/widgets/section_counter_row.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../constants/app_colors.dart';

/// Single row in the "Sections Included" list on the Portfolio Summary screen.
/// Left: section name. Right: item count (bold if > 0).
class SectionCounterRow extends StatelessWidget {
  const SectionCounterRow({
    super.key,
    required this.name,
    required this.count,
    this.isLast = false,
  });

  final String name;
  final int count;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                count.toString(),
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight:
                      count > 0 ? FontWeight.w700 : FontWeight.w400,
                  color: count > 0
                      ? AppColors.primary
                      : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          const Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: AppColors.divider,
          ),
      ],
    );
  }
}