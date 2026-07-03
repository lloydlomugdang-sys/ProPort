// LOCATION: lib/screens/files/college_report_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/grad_app_bar.dart';
import '../../widgets/primary_button.dart';

class CollegeReportScreen extends StatefulWidget {
  const CollegeReportScreen({super.key});

  @override
  State<CollegeReportScreen> createState() => _CollegeReportScreenState();
}

class _CollegeReportScreenState extends State<CollegeReportScreen> {
  bool _isSubmitting = false;
  final List<int?> _answers = List.filled(6, null);

  static const List<String> _options = [
    'Very Often', 'Often', 'Sometimes', 'Never',
  ];

  static const List<String> _questions = [
    'Asked questions in class or contributed to class discussions',
    'Made a class presentation',
    'Prepared two or more drafts of a paper or assignment before turning it in',
    'Worked on a paper or project that required integrating ideas or information from various sources',
    'Came to class without completing readings or assignments',
    'Worked with other students on projects during class',
  ];

  Future<void> _onSubmit() async {
    final unanswered = _answers.indexWhere((a) => a == null);
    if (unanswered != -1) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Please answer all questions before submitting.',
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: AppColors.warning,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ));
      return;
    }

    setState(() => _isSubmitting = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        'College Report submitted successfully!',
        style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
      ),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ));

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const GradBackAppBar(title: 'College Report'),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The College Report', style: AppTextStyles.h3),
            const SizedBox(height: 10),
            Text(
              'During the current school year, about how often have you done each of the following?',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 20),
            ...List.generate(_questions.length, (i) {
              return _QuestionCard(
                index: i,
                question: _questions[i],
                options: _options,
                selectedIndex: _answers[i],
                onChanged: (val) => setState(() => _answers[i] = val),
              );
            }),
            const SizedBox(height: 28),
            PrimaryButton(
              label: 'Submit Report',
              icon: Icons.check_circle_outline_rounded,
              onPressed: _onSubmit,
              isLoading: _isSubmitting,
              height: 54,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.index,
    required this.question,
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
  });

  final int index;
  final String question;
  final List<String> options;
  final int? selectedIndex;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final letter = String.fromCharCode('a'.codeUnitAt(0) + index);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$letter. $question',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textPrimary,
              height: 1.55,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(options.length, (optIdx) {
              return _RadioOption(
                label: options[optIdx],
                isSelected: selectedIndex == optIdx,
                onTap: () => onChanged(optIdx),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _RadioOption extends StatelessWidget {
  const _RadioOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? AppColors.primary : Colors.transparent,
              border: Border.all(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.inputBorder,
                width: 1.8,
              ),
            ),
            child: isSelected
                ? const Icon(Icons.check, size: 13, color: Colors.white)
                : null,
          ),
          const SizedBox(height: 5),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppTextStyles.labelSmall.copyWith(
              fontSize: 9.5,
              color: isSelected ? AppColors.primary : AppColors.textMuted,
              fontWeight:
                  isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}