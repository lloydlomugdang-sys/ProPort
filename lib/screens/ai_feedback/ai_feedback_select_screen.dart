import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import 'ai_feedback_result_screen.dart';

class AiFeedbackSelectScreen extends StatelessWidget {
  const AiFeedbackSelectScreen({super.key});

  void _goToResult(BuildContext context, String selectedData) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiFeedbackResultScreen(
          selectedData: selectedData,
        ),
      ),
    );
  }

  Widget _optionButton({
    required BuildContext context,
    required String title,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: () {
          _goToResult(context, title);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.input,
          foregroundColor: AppColors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AI Feedback',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Select a section to analyze.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 34),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select Data to Analyze',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 18),

                    _optionButton(
                      context: context,
                      title: 'Profile Bio',
                    ),

                    const SizedBox(height: 12),

                    _optionButton(
                      context: context,
                      title: 'Project Details: Project Title',
                    ),

                    const SizedBox(height: 12),

                    _optionButton(
                      context: context,
                      title: 'Project Details: Project Title',
                    ),

                    const SizedBox(height: 12),

                    _optionButton(
                      context: context,
                      title: 'Skills List',
                    ),

                    const SizedBox(height: 12),

                    _optionButton(
                      context: context,
                      title: 'Analyze Overall Data',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              
            ],
          ),
        ),
      ),
    );
  }
}