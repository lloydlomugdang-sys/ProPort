import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../services/api_client.dart';
import '../../services/portfolio_scope.dart';
import '../../services/portfolio_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/grad_app_bar.dart';
import '../../widgets/primary_button.dart';
import 'models/portfolio_models.dart';
import 'portfolio_info_screen.dart';
import 'portfolio_preview_screen.dart';

class PortfolioListScreen extends StatefulWidget {
  const PortfolioListScreen({super.key});

  static const routeName = '/my-portfolios';

  static void returnToList(BuildContext context) {
    final navigator = Navigator.of(context);
    var foundList = false;
    navigator.popUntil((route) {
      foundList = route.settings.name == routeName;
      return foundList || route.isFirst;
    });
    // The Generate action can now start directly from Home, without a list
    // underneath it. Open the same history screen after closing that flow.
    if (!foundList) {
      navigator.push<void>(
        MaterialPageRoute(
          settings: const RouteSettings(name: routeName),
          builder: (_) => const PortfolioListScreen(),
        ),
      );
    }
  }

  @override
  State<PortfolioListScreen> createState() => _PortfolioListScreenState();
}

class _PortfolioListScreenState extends State<PortfolioListScreen> {
  bool _loadStarted = false;
  String? _errorMessage;
  String? _openingId;
  String? _deletingId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadStarted) return;
    _loadStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool force = false}) async {
    if (!mounted) return;
    setState(() => _errorMessage = null);
    try {
      await PortfolioScope.of(context).loadPortfolios(force: force);
    } on ApiException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Unable to load portfolios. Please try again.',
        );
      }
    }
  }

  Future<void> _create() async {
    await Navigator.push<Object?>(
      context,
      MaterialPageRoute(builder: (_) => const PortfolioInfoScreen()),
    );
  }

  Future<void> _view(PortfolioRecord portfolio) async {
    if (_openingId != null) return;
    setState(() => _openingId = portfolio.id);
    try {
      final loaded = await PortfolioScope.of(
        context,
      ).getPortfolio(portfolio.id);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => PortfolioPreviewScreen(portfolioInfo: loaded.info),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Unable to open the portfolio. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  Future<void> _edit(PortfolioRecord portfolio) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PortfolioInfoScreen(portfolio: portfolio),
      ),
    );
    if (saved == true && mounted) {
      _showMessage('Portfolio updated successfully.');
    }
  }

  Future<void> _delete(PortfolioRecord portfolio) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Delete Portfolio', style: AppTextStyles.h3),
        content: Text(
          'Delete this portfolio? This action cannot be undone.',
          style: AppTextStyles.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingId = portfolio.id);
    try {
      await PortfolioScope.of(context).deletePortfolio(portfolio.id);
      if (mounted) _showMessage('Portfolio deleted successfully.');
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Unable to delete the portfolio. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? AppColors.danger : AppColors.success,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final service = PortfolioScope.of(context);
    final portfolios = service.portfolios;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const GradBackAppBar(title: 'My Portfolios'),
      body: Column(
        children: [
          Expanded(child: _buildContent(service, portfolios)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: PrimaryButton(
              label: 'Create Portfolio',
              icon: Icons.add_rounded,
              onPressed: _create,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    PortfolioService service,
    List<PortfolioRecord> portfolios,
  ) {
    if (service.isLoading && !service.hasLoaded) {
      return const Center(
        key: Key('portfolio-loading'),
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_errorMessage != null && portfolios.isEmpty) {
      return Center(
        key: const Key('portfolio-error'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _load(force: true),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (portfolios.isEmpty) {
      return const EmptyState(
        key: Key('portfolio-empty'),
        message: 'No portfolios yet.',
        subtitle: 'Create one to save your portfolio title-page information.',
        icon: Icons.description_outlined,
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      color: AppColors.primary,
      child: ListView.separated(
        key: const Key('portfolio-list'),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        itemCount: portfolios.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, index) => _PortfolioCard(
          portfolio: portfolios[index],
          isOpening: _openingId == portfolios[index].id,
          isDeleting: _deletingId == portfolios[index].id,
          onView: () => _view(portfolios[index]),
          onEdit: () => _edit(portfolios[index]),
          onDelete: () => _delete(portfolios[index]),
        ),
      ),
    );
  }
}

class _PortfolioCard extends StatelessWidget {
  const _PortfolioCard({
    required this.portfolio,
    required this.isOpening,
    required this.isDeleting,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  final PortfolioRecord portfolio;
  final bool isOpening;
  final bool isDeleting;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final info = portfolio.info;
    final subtitleParts = [
      if (info.courseCode.isNotEmpty) info.courseCode,
      if (info.course.isNotEmpty) info.course,
    ];
    return Container(
      key: Key('portfolio-${portfolio.id}'),
      padding: const EdgeInsets.fromLTRB(16, 16, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(info.fullName, style: AppTextStyles.h3),
          const SizedBox(height: 4),
          Text(
            subtitleParts.isEmpty
                ? 'Course not provided'
                : subtitleParts.join(' · '),
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 2),
          Text(info.yearAndSection, style: AppTextStyles.labelMedium),
          const SizedBox(height: 2),
          Text(info.formattedSchedule, style: AppTextStyles.labelMedium),
          const SizedBox(height: 2),
          Text(info.instructorName, style: AppTextStyles.labelMedium),
          if (info.semesterAndYear.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(info.semesterAndYear, style: AppTextStyles.labelMedium),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                key: Key('view-${portfolio.id}'),
                onPressed: isOpening ? null : onView,
                icon: isOpening
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('View'),
              ),
              IconButton(
                key: Key('edit-${portfolio.id}'),
                tooltip: 'Edit portfolio',
                onPressed: isDeleting ? null : onEdit,
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
              IconButton(
                key: Key('delete-${portfolio.id}'),
                tooltip: 'Delete portfolio',
                onPressed: isDeleting ? null : onDelete,
                icon: isDeleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline_rounded, size: 20),
                color: AppColors.danger,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
