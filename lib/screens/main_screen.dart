// LOCATION: lib/screens/main_screen.dart
// REPLACE the existing file entirely.
// CHANGES: Add FAB now navigates to AddFileScreen as a full screen.
//          Profile tab now uses the shared ProfileScreen.

import 'package:flutter/material.dart';
import 'home/home_screen.dart';
import 'files/files_screen.dart';
import 'files/add_file_screen.dart';
import 'profile/profile_screen.dart';
import 'settings/settings_screen.dart' show SettingsScreen;
import '../widgets/bottom_nav_bar.dart';
import '../constants/app_colors.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  List<Widget> get _pages => [
        const HomeScreen(),
        const FilesScreen(),
        const ProfileScreen(),
        const SettingsScreen(),
      ];

  void _onTabChanged(int index) {
    setState(() => _currentIndex = index);
  }

  /// Add FAB opens AddFileScreen as a full-screen push.
  /// Wireframe shows a full screen with back arrow — not a bottom sheet.
  void _onAddTapped() {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, __, ___) => const AddFileScreen(),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
  top: false,
  bottom: false,
  child: IndexedStack(
    index: _currentIndex,
    children: _pages,
  ),
),
      bottomNavigationBar: GradBottomNavBar(
        currentIndex: _currentIndex,
        onTabChanged: _onTabChanged,
        onAddTapped: _onAddTapped,
      ),
    );
  }
}