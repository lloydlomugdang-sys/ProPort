// LOCATION: lib/screens/portfolio/widgets/step_indicator.dart

import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';

/// Three-dot step indicator matching the wireframe.
///
/// Dots:
///   - Current step  → hollow circle (outline only)
///   - Completed     → filled solid circle
///   - Future step   → filled solid circle (dimmer)
///
/// Wireframe step patterns:
///   Step 1: ○ ● ●
///   Step 2: ● ○ ●
///   Step 3: ● ● ○
class StepIndicator extends StatelessWidget {
  const StepIndicator({
    super.key,
    required this.currentStep, // 1-based (1, 2, or 3)
    this.totalSteps = 3,
  });

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalSteps, (index) {
        final stepNumber = index + 1;
        final isCurrent = stepNumber == currentStep;

        return Padding(
          padding: EdgeInsets.only(right: index < totalSteps - 1 ? 8 : 0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            width: isCurrent ? 10 : 10,
            height: isCurrent ? 10 : 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCurrent ? Colors.transparent : Colors.white,
              border: Border.all(
                color: Colors.white,
                width: isCurrent ? 2.0 : 0,
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Step indicator on a light background (used below the bottom nav area).
/// Matches the wireframe's indicator row that sits just above the bottom nav.
class StepIndicatorLight extends StatelessWidget {
  const StepIndicatorLight({
    super.key,
    required this.currentStep,
    this.totalSteps = 3,
  });

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalSteps, (index) {
        final stepNumber = index + 1;
        final isCurrent = stepNumber == currentStep;

        return Padding(
          padding: EdgeInsets.only(right: index < totalSteps - 1 ? 8 : 0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCurrent
                  ? Colors.transparent
                  : AppColors.primary,
              border: Border.all(
                color: AppColors.primary,
                width: 2.0,
              ),
            ),
          ),
        );
      }),
    );
  }
}