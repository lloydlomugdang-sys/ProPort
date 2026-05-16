import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';
import '../editor_logic/portfolio_template_logic.dart';

Future<PortfolioTemplateType?> showPortfolioTemplatesDialog(
  BuildContext context,
) {
  return showDialog<PortfolioTemplateType>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 26),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(
            maxWidth: 430,
          ),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Portfolio Layouts',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                    },
                    icon: const Icon(
                      Icons.close,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 4),

              const Text(
                'Choose a starter layout for your portfolio canvas.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 18),

              _TemplateCard(
                title: 'Blank Portfolio',
                subtitle: 'Start with an empty canvas.',
                icon: Icons.crop_square_outlined,
                onTap: () {
                  Navigator.pop(
                    dialogContext,
                    PortfolioTemplateType.blank,
                  );
                },
              ),

              _TemplateCard(
                title: 'Student Profile Layout',
                subtitle: 'Starter layout for personal profile portfolios.',
                icon: Icons.person_outline,
                onTap: () {
                  Navigator.pop(
                    dialogContext,
                    PortfolioTemplateType.studentProfile,
                  );
                },
              ),

              _TemplateCard(
                title: 'Project Showcase Layout',
                subtitle: 'Starter layout for presenting projects and works.',
                icon: Icons.dashboard_customize_outlined,
                onTap: () {
                  Navigator.pop(
                    dialogContext,
                    PortfolioTemplateType.projectShowcase,
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _TemplateCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _TemplateCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.input,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                icon,
                color: AppColors.white,
                size: 23,
              ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),

            const Icon(
              Icons.arrow_forward_ios,
              color: AppColors.textSecondary,
              size: 15,
            ),
          ],
        ),
      ),
    );
  }
}