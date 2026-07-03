// LOCATION: lib/screens/profile/profile_screen.dart
// REPLACE the existing file entirely.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
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
  @override
  void initState() {
    super.initState();
    // Listen for profile updates from EditProfileScreen
    userProfileNotifier.addListener(_onProfileChanged);
  }

  @override
  void dispose() {
    userProfileNotifier.removeListener(_onProfileChanged);
    super.dispose();
  }

  void _onProfileChanged() {
    if (mounted) setState(() {});
  }

  void _onEditTap() {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, __, ___) => const EditProfileScreen(),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
                parent: anim, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = userProfileNotifier.profile;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: GradAppBar(
        title: 'Profile',
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                color: AppColors.headerText, size: 22),
            onPressed: _onEditTap,
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
        child: Column(
          children: [
            // ── Avatar + name ───────────────────────────────────────
            ProfileAvatar(
              avatarPath: profile.avatarPath,
              size: 110,
            ),
            const SizedBox(height: 16),
            Text(
              profile.fullName,
              style: AppTextStyles.h2.copyWith(color: AppColors.primary),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 28),

            // ── Info card ────────────────────────────────────────────
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
                    value: profile.program,
                  ),
                  ProfileInfoRow(
                    icon: Icons.calendar_today_outlined,
                    value: profile.yearLevel,
                  ),
                  ProfileInfoRow(
                    icon: Icons.account_balance_outlined,
                    value: profile.school,
                    isLast: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}