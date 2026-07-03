// LOCATION: lib/widgets/bottom_nav_bar.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

/// GradPort v2 — 5-tab bottom navigation.
/// Home | Files | Add (+) | Profile | Settings
class GradBottomNavBar extends StatelessWidget {
  const GradBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTabChanged,
    required this.onAddTapped,
  });

  /// 0=Home  1=Files  2=Profile  3=Settings
  final int currentIndex;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onAddTapped;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: AppColors.navBackground,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _NavItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: 'Home',
              isActive: currentIndex == 0,
              onTap: () => onTabChanged(0),
            ),
            _NavItem(
              icon: Icons.folder_outlined,
              activeIcon: Icons.folder_rounded,
              label: 'Files',
              isActive: currentIndex == 1,
              onTap: () => onTabChanged(1),
            ),
            // Centre FAB-style Add button
            Expanded(
              child: GestureDetector(
                onTap: onAddTapped,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.add,
                        color: AppColors.primary,
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Add',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.navUnselected,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _NavItem(
              icon: Icons.person_outline,
              activeIcon: Icons.person_rounded,
              label: 'Profile',
              isActive: currentIndex == 2,
              onTap: () => onTabChanged(2),
            ),
            _NavItem(
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings_rounded,
              label: 'Settings',
              isActive: currentIndex == 3,
              onTap: () => onTabChanged(3),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.navSelected : AppColors.navUnselected;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isActive ? activeIcon : icon,
                key: ValueKey(isActive),
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight:
                    isActive ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}