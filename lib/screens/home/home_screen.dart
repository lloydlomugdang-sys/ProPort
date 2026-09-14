// LOCATION: lib/screens/home/home_screen.dart

import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../services/auth_models.dart';
import '../../services/auth_scope.dart';
import '../../services/document_models.dart';
import '../../services/document_scope.dart';
import '../../widgets/grad_app_bar.dart';
import '../../widgets/section_header.dart';
import '../../widgets/tracker_row.dart';
import '../../widgets/file_count_row.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/primary_button.dart';
import '../portfolio/portfolio_list_screen.dart';
import '../portfolio/portfolio_info_screen.dart';
import '../files/files_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  bool _documentLoadRequested = false;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceCtrl,
            curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
          ),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entranceCtrl.forward();
    });
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_documentLoadRequested) return;
    _documentLoadRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      DocumentScope.of(context).load().catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthScope.of(context).user;
    final documents = DocumentScope.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const GradAppBar(title: 'Dashboard'),
      // FIX: FadeTransition and SlideTransition were wrapping the
      // SingleChildScrollView, which caused the scroll view to inherit a
      // bounded height from the transition widget. On small screens this
      // meant the scroll view's internal content (663px+) could not scroll
      // freely, producing a 17px RenderFlex overflow.
      // Solution: move both transitions INSIDE the scroll view so the
      // scroll view itself always fills the full body height unconstrained.
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 110),
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildUserCard(currentUser),
                const SizedBox(height: 20),
                if (!documents.hasLoadedDocuments)
                  _DocumentMetricsState(
                    isLoading: documents.isLoading,
                    message: documents.errorMessage,
                    onRetry: () =>
                        documents.load(force: true).catchError((_) {}),
                  )
                else ...[
                  StatCard(
                    label: 'Total Files',
                    value: documents.summary.totalCount.toString(),
                    icon: Icons.folder_copy_rounded,
                  ),
                  const SizedBox(height: 24),
                  const SectionHeader(title: 'Portfolio Tracker'),
                  const SizedBox(height: 10),
                  _buildPortfolioTracker(documents.summary),
                  const SizedBox(height: 24),
                  const SectionHeader(title: 'Uploaded Files'),
                  const SizedBox(height: 10),
                  _buildUploadedFiles(documents.summary),
                ],
                const SizedBox(height: 28),
                // ── Generate Portfolio → navigates to PortfolioInfoScreen ──
                PrimaryButton(
                  label: 'Generate Portfolio',
                  onPressed: _onGeneratePortfolio,
                  height: 54,
                ),
                TextButton(
                  onPressed: () => _onGeneratePortfolio(showHistory: true),
                  child: const Text('My Portfolios'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Navigate to the Generate Portfolio workflow ───────────────────────────
  void _onGeneratePortfolio({bool showHistory = false}) {
    Navigator.push(
      context,
      PageRouteBuilder(
        settings: RouteSettings(
          name: showHistory
              ? PortfolioListScreen.routeName
              : '/generate-portfolio',
        ),
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, _, _) => showHistory
            ? const PortfolioListScreen()
            : const PortfolioInfoScreen(),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(0, 0.05),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
                ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(AuthUser? user) {
    final fullName = user == null
        ? null
        : '${user.firstName} ${user.lastName}'.trim();
    final program = user?.program.trim();
    final yearLevel = user?.yearLevel.trim();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
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
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.25),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: AppColors.primary,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: user == null
                ? Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Loading profile...',
                        style: AppTextStyles.bodySmall,
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName!.isEmpty ? 'Name not provided' : fullName,
                        style: AppTextStyles.h3,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        program!.isEmpty ? 'Program not set' : program,
                        style: AppTextStyles.bodySmall,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        yearLevel!.isEmpty ? 'Year level not set' : yearLevel,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        user.school.trim().isEmpty
                            ? 'School not set'
                            : user.school.trim(),
                        style: AppTextStyles.bodySmall,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortfolioTracker(DocumentSummary summary) {
    final trackerItems = [
      _TrackerItem(
        'Curriculum Vitae',
        _trackerStatus(summary.categoryCount('curriculum-vitae')),
      ),
      _TrackerItem(
        'Scholastic Record',
        _trackerStatus(summary.categoryCount('scholastic-record')),
      ),
      _TrackerItem(
        'College Report',
        _trackerStatus(summary.categoryCount('college-report')),
      ),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
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
        children: trackerItems.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          return Column(
            children: [
              TrackerRow(
                label: item.label,
                status: item.status,
                onTap: () => _openCategory(item.label),
              ),
              if (idx < trackerItems.length - 1)
                const Divider(height: 1, color: AppColors.divider),
            ],
          );
        }).toList(),
      ),
    );
  }

  TrackerStatus _trackerStatus(int count) =>
      count == 0 ? TrackerStatus.none : TrackerStatus.incomplete;

  Widget _buildUploadedFiles(DocumentSummary summary) {
    final uploadedFiles = [
      _FileCountItem('Creative Titles', summary.creativeTitleCount),
      _FileCountItem('Certificates', summary.categoryCount('certificates')),
      _FileCountItem(
        'Accomplishments',
        summary.categoryCount('accomplishments'),
      ),
      _FileCountItem(
        'Other Achievements',
        summary.categoryCount('other-achievements'),
      ),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
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
        children: uploadedFiles.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          return Column(
            children: [
              FileCountRow(
                label: item.label,
                count: item.count,
                onTap: () => _openCategory(item.label),
              ),
              if (idx < uploadedFiles.length - 1)
                const Divider(height: 1, color: AppColors.divider),
            ],
          );
        }).toList(),
      ),
    );
  }

  void _openCategory(String label) {
    const categories = {
      'Curriculum Vitae': 'curriculum-vitae',
      'Scholastic Record': 'scholastic-record',
      'Certificates': 'certificates',
      'Accomplishments': 'accomplishments',
      'Other Achievements': 'other-achievements',
      'College Report': 'college-report',
    };
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FilesScreen(
          initialCategoryKey: categories[label],
          initialFolderKey: label == 'Creative Titles'
              ? 'creative-title'
              : null,
        ),
      ),
    );
  }
}

class _TrackerItem {
  const _TrackerItem(this.label, this.status);
  final String label;
  final TrackerStatus status;
}

class _FileCountItem {
  const _FileCountItem(this.label, this.count);
  final String label;
  final int count;
}

class _DocumentMetricsState extends StatelessWidget {
  const _DocumentMetricsState({
    required this.isLoading,
    required this.message,
    required this.onRetry,
  });

  final bool isLoading;
  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          if (isLoading)
            const CircularProgressIndicator(color: AppColors.primary)
          else
            const Icon(
              Icons.cloud_off_outlined,
              color: AppColors.textMuted,
              size: 30,
            ),
          const SizedBox(height: 10),
          Text(
            isLoading
                ? 'Loading your documents...'
                : message ?? 'Document totals are unavailable.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall,
          ),
          if (!isLoading)
            TextButton(onPressed: onRetry, child: const Text('Try Again')),
        ],
      ),
    );
  }
}
