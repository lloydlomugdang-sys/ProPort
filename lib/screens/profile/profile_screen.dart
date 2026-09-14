import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../auth/widgets/auth_form_feedback.dart';
import '../../services/auth_scope.dart';
import '../../widgets/grad_app_bar.dart';
import 'edit_profile_screen.dart';
import 'models/user_profile_model.dart';
import 'widgets/profile_avatar.dart';
import 'widgets/profile_info_row.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loadStarted = false;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadStarted) return;
    _loadStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await AuthScope.of(context).fetchCurrentUser();
      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _safeErrorMessage(error);
      });
    }
  }

  Future<void> _onEditTap(UserProfile profile) async {
    await Navigator.push<void>(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, _, _) => EditProfileScreen(profile: profile),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(0.04, 0),
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

  String _safeErrorMessage(Object error) {
    return authFormError(error);
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    final user = auth.user;
    final profile = user == null ? null : UserProfile.fromAuthUser(user);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: GradAppBar(
        title: 'Profile',
        actions: [
          IconButton(
            icon: const Icon(
              Icons.edit_outlined,
              color: AppColors.headerText,
              size: 22,
            ),
            onPressed: profile == null || _isLoading
                ? null
                : () => _onEditTap(profile),
            tooltip: 'Edit profile',
          ),
        ],
      ),
      body: _buildBody(profile),
    );
  }

  Widget _buildBody(UserProfile? profile) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_errorMessage != null || profile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage ?? 'Unable to load your profile.',
                style: AppTextStyles.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadProfile,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      child: Column(
        children: [
          const ProfileAvatar(size: 110),
          const SizedBox(height: 16),
          Text(
            profile.fullName,
            style: AppTextStyles.h2.copyWith(color: AppColors.primary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          Container(
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
              children: [
                ProfileInfoRow(
                  icon: Icons.email_outlined,
                  value: profile.email,
                ),
                ProfileInfoRow(
                  icon: Icons.school_outlined,
                  value: profile.program.trim().isEmpty
                      ? 'Program not set'
                      : profile.program,
                ),
                ProfileInfoRow(
                  icon: Icons.calendar_today_outlined,
                  value: profile.yearLevel.trim().isEmpty
                      ? 'Year level not set'
                      : profile.yearLevel,
                ),
                ProfileInfoRow(
                  icon: Icons.account_balance_outlined,
                  value: profile.school.trim().isEmpty
                      ? 'School not set'
                      : profile.school,
                  isLast: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
