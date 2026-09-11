import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../constants/app_colors.dart';
import '../models/portfolio_schedule.dart';

typedef ScheduleTimePicker =
    Future<TimeOfDay?> Function(BuildContext context, TimeOfDay initialTime);

class PortfolioSchedulePicker extends StatelessWidget {
  const PortfolioSchedulePicker({
    super.key,
    required this.day,
    required this.startTime,
    required this.endTime,
    required this.onDayChanged,
    required this.onStartTimeChanged,
    required this.onEndTimeChanged,
    this.legacyValue,
    this.timePicker,
  });

  final String? day;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final ValueChanged<String?> onDayChanged;
  final ValueChanged<TimeOfDay> onStartTimeChanged;
  final ValueChanged<TimeOfDay> onEndTimeChanged;
  final String? legacyValue;
  final ScheduleTimePicker? timePicker;

  Future<void> _pick(
    BuildContext context, {
    required TimeOfDay initialTime,
    required ValueChanged<TimeOfDay> onSelected,
  }) async {
    final selected = await (timePicker ?? _showMaterialTimePicker)(
      context,
      initialTime,
    );
    if (selected != null) onSelected(selected);
  }

  static Future<TimeOfDay?> _showMaterialTimePicker(
    BuildContext context,
    TimeOfDay initialTime,
  ) {
    return showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle = GoogleFonts.poppins(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: AppColors.textPrimary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Schedule', style: labelStyle),
            Text(
              '*',
              style: labelStyle.copyWith(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _fieldContainer(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: const Key('schedule-day'),
              value: day,
              hint: Text('Select day', style: _valueStyle(false)),
              isExpanded: true,
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppColors.textMuted,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              borderRadius: BorderRadius.circular(12),
              dropdownColor: Colors.white,
              onChanged: onDayChanged,
              items: portfolioScheduleDays
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(value, style: _valueStyle(true)),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _TimeField(
                key: const Key('schedule-start-time'),
                label: 'Start Time',
                value: startTime,
                onTap: () => _pick(
                  context,
                  initialTime: startTime ?? const TimeOfDay(hour: 8, minute: 0),
                  onSelected: onStartTimeChanged,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TimeField(
                key: const Key('schedule-end-time'),
                label: 'End Time',
                value: endTime,
                onTap: () => _pick(
                  context,
                  initialTime:
                      endTime ??
                      _oneHourAfter(
                        startTime ?? const TimeOfDay(hour: 8, minute: 0),
                      ),
                  onSelected: onEndTimeChanged,
                ),
              ),
            ),
          ],
        ),
        if (legacyValue != null && legacyValue!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Existing schedule: ${legacyValue!.trim()}. Select a day and times to replace it.',
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: AppColors.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  static Widget _fieldContainer({required Widget child}) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.inputBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  static TextStyle _valueStyle(bool selected) => GoogleFonts.poppins(
    fontSize: 14,
    color: selected ? AppColors.textPrimary : AppColors.textMuted,
  );

  static TimeOfDay _oneHourAfter(TimeOfDay value) => TimeOfDay(
    hour: value.hour < 23 ? value.hour + 1 : 23,
    minute: value.hour < 23 ? value.minute : 59,
  );
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final TimeOfDay? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: PortfolioSchedulePicker._fieldContainer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.poppins(
                        fontSize: 9.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                    Text(
                      value == null
                          ? '--:--'
                          : PortfolioSchedule.formatTime(value!),
                      style: PortfolioSchedulePicker._valueStyle(value != null),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.schedule_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
