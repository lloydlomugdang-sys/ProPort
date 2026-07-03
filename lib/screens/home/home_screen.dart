// LOCATION: lib/screens/home/home_screen.dart
// CHANGE: Generate Portfolio button now navigates to PortfolioInfoScreen.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/grad_app_bar.dart';
import '../../widgets/section_header.dart';
import '../../widgets/tracker_row.dart';
import '../../widgets/file_count_row.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/primary_button.dart';
import '../portfolio/portfolio_info_screen.dart';

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

  final String _userName   = 'John Dela Cruz';
  final String _degree     = 'BS Information Technology';
  final String _year       = '3rd year';
  final int    _totalFiles = 43;

  final List<_TrackerItem> _trackerItems = [
    _TrackerItem('Curriculum Vitae',  TrackerStatus.none),
    _TrackerItem('Scholastic Record', TrackerStatus.complete),
    _TrackerItem('College Report',    TrackerStatus.incomplete),
  ];

  final List<_FileCountItem> _uploadedFiles = [
    _FileCountItem('Creative Titles',     0),
    _FileCountItem('Certificates',       11),
    _FileCountItem('Accomplishments',    30),
    _FileCountItem('Other Achievements',  2),
  ];

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
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
    ));
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
  Widget build(BuildContext context) {
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
        padding: EdgeInsets.fromLTRB(
  20,
  20,
  20,
  60 + MediaQuery.of(context).padding.bottom,
),
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildUserCard(),
                const SizedBox(height: 20),
                StatCard(
                  label: 'Total Files',
                  value: _totalFiles.toString(),
                  icon: Icons.folder_copy_rounded,
                ),
                const SizedBox(height: 24),
                const SectionHeader(title: 'Portfolio Tracker'),
                const SizedBox(height: 10),
                _buildPortfolioTracker(),
                const SizedBox(height: 24),
                const SectionHeader(title: 'Uploaded Files'),
                const SizedBox(height: 10),
                _buildUploadedFiles(),
                const SizedBox(height: 28),
                // ── Generate Portfolio → navigates to PortfolioInfoScreen ──
                PrimaryButton(
                  label: 'Generate Portfolio',
                  icon: Icons.auto_awesome_rounded,
                  onPressed: _onGeneratePortfolio,
                  height: 54,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Navigate to the Generate Portfolio workflow ───────────────────────────
  void _onGeneratePortfolio() {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, __, ___) => const PortfolioInfoScreen(),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.05),
              end: Offset.zero,
            ).animate(CurvedAnimation(
                parent: anim, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard() {
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
            child: const Icon(Icons.person_rounded,
                color: AppColors.primary, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_userName, style: AppTextStyles.h3),
                const SizedBox(height: 2),
                Text(_degree, style: AppTextStyles.bodySmall),
                const SizedBox(height: 1),
                Text(
                  _year,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortfolioTracker() {
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
        children: _trackerItems.asMap().entries.map((entry) {
          final idx  = entry.key;
          final item = entry.value;
          return Column(
            children: [
              TrackerRow(
                label: item.label,
                status: item.status,
                onTap: () => _showSnack('Opened: ${item.label}'),
              ),
              if (idx < _trackerItems.length - 1)
                const Divider(height: 1, color: AppColors.divider),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildUploadedFiles() {
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
        children: _uploadedFiles.asMap().entries.map((entry) {
          final idx  = entry.key;
          final item = entry.value;
          return Column(
            children: [
              FileCountRow(
                label: item.label,
                count: item.count,
                onTap: () => _showSnack('Opened: ${item.label}'),
              ),
              if (idx < _uploadedFiles.length - 1)
                const Divider(height: 1, color: AppColors.divider),
            ],
          );
        }).toList(),
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white)),
      backgroundColor: AppColors.primary,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      duration: const Duration(seconds: 1),
    ));
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