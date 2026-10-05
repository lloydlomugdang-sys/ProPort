// LOCATION: lib/screens/files/widgets/date_picker_field.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../constants/app_colors.dart';

/// Labelled date input field that opens a Material date picker.
class DatePickerField extends StatelessWidget {
  const DatePickerField({
    super.key,
    required this.label,
    required this.selectedDate,
    required this.onDateSelected,
    this.required = false,
    this.enabled = true,
  });

  final String label;
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final bool required;
  final bool enabled;

  String get _displayText {
    if (selectedDate == null) return 'MM/DD/YYYY';
    return '${selectedDate!.month.toString().padLeft(2, '0')}/'
        '${selectedDate!.day.toString().padLeft(2, '0')}/'
        '${selectedDate!.year}';
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: selectedDate != null && selectedDate!.isBefore(DateTime(2000))
          ? selectedDate!
          : DateTime(2000),
      lastDate: selectedDate != null && selectedDate!.isAfter(DateTime(2100))
          ? selectedDate!
          : DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) onDateSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            if (required)
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

        // Field
        GestureDetector(
          onTap: enabled ? () => _pickDate(context) : null,
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: enabled ? Colors.white : AppColors.cardBorder.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _displayText,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: !enabled
                          ? AppColors.textMuted
                          : (selectedDate != null
                              ? AppColors.textPrimary
                              : AppColors.textMuted),
                    ),
                  ),
                ),
                Icon(
                  Icons.calendar_today_rounded,
                  size: 18,
                  color: enabled ? AppColors.primary : AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
