// LOCATION: lib/widgets/tracker_row.dart

import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

enum TrackerStatus { none, complete, incomplete }

class TrackerRow extends StatelessWidget {
  const TrackerRow({
    super.key,
    required this.label,
    required this.status,
    this.onTap,
  });

  final String label;
  final TrackerStatus status;
  final VoidCallback? onTap;

  String get _statusText => switch (status) {
        TrackerStatus.none       => 'None',
        TrackerStatus.complete   => 'Complete',
        TrackerStatus.incomplete => 'Incomplete',
      };

  Color get _chipBg => switch (status) {
        TrackerStatus.none       => AppColors.statusNoneBg,
        TrackerStatus.complete   => AppColors.statusCompleteBg,
        TrackerStatus.incomplete => AppColors.statusIncompleteBg,
      };

  Color get _chipText => switch (status) {
        TrackerStatus.none       => AppColors.statusNoneText,
        TrackerStatus.complete   => AppColors.statusCompleteText,
        TrackerStatus.incomplete => AppColors.statusIncompleteText,
      };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textPrimary),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: _chipBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _statusText,
                style: AppTextStyles.chipText.copyWith(color: _chipText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}