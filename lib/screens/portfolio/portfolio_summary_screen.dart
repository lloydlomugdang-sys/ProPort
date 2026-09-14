import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../services/api_client.dart';
import '../../services/portfolio_scope.dart';
import '../../widgets/grad_app_bar.dart';
import '../../widgets/primary_button.dart';
import 'models/portfolio_models.dart';
import 'portfolio_list_screen.dart';
import 'portfolio_preview_screen.dart';

/// Confirmation for the owner-scoped portfolio record returned after creation.
class PortfolioSummaryScreen extends StatefulWidget {
  const PortfolioSummaryScreen({super.key, required this.portfolio});

  final PortfolioRecord portfolio;

  @override
  State<PortfolioSummaryScreen> createState() => _PortfolioSummaryScreenState();
}

class _PortfolioSummaryScreenState extends State<PortfolioSummaryScreen> {
  bool _opening = false;
  String? _errorMessage;

  Future<void> _viewPortfolio() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _errorMessage = null;
    });
    try {
      final saved = await PortfolioScope.of(
        context,
      ).getPortfolio(widget.portfolio.id);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => PortfolioPreviewScreen(portfolioInfo: saved.info),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _errorMessage = error is ApiException
              ? error.message
              : 'Unable to open the portfolio. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.portfolio.info;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const GradBackAppBar(title: 'Portfolio Saved'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 56,
                      color: AppColors.success,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Saved to My Portfolios',
                      style: AppTextStyles.h3,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(info.fullName, style: AppTextStyles.bodyMedium),
                    if (info.course.trim().isNotEmpty)
                      Text(info.course, style: AppTextStyles.bodySmall),
                    if (info.courseCode.trim().isNotEmpty)
                      Text(info.courseCode, style: AppTextStyles.bodySmall),
                    Text(
                      info.formattedSchedule,
                      style: AppTextStyles.labelMedium,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Your portfolio information is saved to your account. '
                      'You can reopen it anytime from Home → My Portfolios.',
                      style: AppTextStyles.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'PDF/DOCX export is not available yet.',
                      style: AppTextStyles.labelMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (_errorMessage != null) ...[
                Text(
                  _errorMessage!,
                  style: AppTextStyles.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
              ],
              PrimaryButton(
                label: 'View Portfolio',
                icon: Icons.visibility_outlined,
                isLoading: _opening,
                onPressed: _viewPortfolio,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => PortfolioListScreen.returnToList(context),
                child: const Text('Back to My Portfolios'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
