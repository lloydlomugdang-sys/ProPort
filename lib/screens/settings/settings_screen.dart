import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../auth/login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool notificationsEnabled = true;

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  void _showInfoDialog({
    required String title,
    required String content,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: AppColors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            content,
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text(
                'Close',
                style: TextStyle(
                  color: AppColors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _logoutUser() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Log Out',
            style: TextStyle(
              color: AppColors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            'Are you sure you want to log out?',
            style: TextStyle(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);

                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LoginScreen(),
                  ),
                  (route) => false,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.input,
                foregroundColor: AppColors.white,
                elevation: 0,
              ),
              child: const Text(
                'Log Out',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _settingsSection({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color iconColor = AppColors.white,
    Color titleColor = AppColors.white,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: iconColor,
              size: 23,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
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

  Widget _notificationTile() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.notifications_none,
            color: AppColors.white,
            size: 23,
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifications',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Enable or disable app alerts.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: notificationsEnabled,
            activeColor: AppColors.white,
            activeTrackColor: AppColors.input,
            inactiveThumbColor: AppColors.textSecondary,
            inactiveTrackColor: AppColors.darkTeal,
            onChanged: (value) {
              setState(() {
                notificationsEnabled = value;
              });

              _showMessage(
                value ? 'Notifications enabled.' : 'Notifications disabled.',
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _logoutButton() {
    return Center(
      child: SizedBox(
        width: 190,
        height: 44,
        child: ElevatedButton(
          onPressed: _logoutUser,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            side: const BorderSide(
              color: AppColors.border,
            ),
          ),
          child: const Text(
            'Log Out',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
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
                'Settings',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 6),

              const Text(
                'Manage your account and app preferences.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 30),

              _settingsSection(
                title: 'Account',
                children: [
                  _settingsTile(
                    icon: Icons.lock_outline,
                    title: 'Change Password',
                    subtitle: 'Update your account password.',
                    onTap: () {
                      _showMessage('Change Password UI will be added next.');
                    },
                  ),
                  _settingsTile(
                    icon: Icons.delete_outline,
                    title: 'Delete Account',
                    subtitle: 'Prototype delete account option.',
                    iconColor: AppColors.danger,
                    titleColor: AppColors.danger,
                    onTap: () {
                      _showInfoDialog(
                        title: 'Delete Account',
                        content:
                            'This is only a prototype option. Actual account deletion will be added in the next development phase.',
                      );
                    },
                  ),
                ],
              ),

              _settingsSection(
                title: 'Preferences',
                children: [
                  _notificationTile(),
                ],
              ),

              _settingsSection(
                title: 'Information & Privacy',
                children: [
                  _settingsTile(
                    icon: Icons.info_outline,
                    title: 'About ProPort',
                    subtitle: 'Learn more about the ProPort app.',
                    onTap: () {
                      _showInfoDialog(
                        title: 'About ProPort',
                        content:
                            'ProPort is a mobile career development and portfolio builder application for college students. It helps users organize their profile, skills, portfolio projects, career tasks, and documents.',
                      );
                    },
                  ),
                  _settingsTile(
                    icon: Icons.auto_awesome,
                    title: 'About AI Feedback',
                    subtitle: 'Information about the feedback feature.',
                    onTap: () {
                      _showInfoDialog(
                        title: 'About AI Feedback',
                        content:
                            'The AI Feedback feature is planned to help users improve their portfolio based on selected career data. For now, it is shown as a UI prototype.',
                      );
                    },
                  ),
                  _settingsTile(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Privacy Notice',
                    subtitle: 'View privacy-related information.',
                    onTap: () {
                      _showInfoDialog(
                        title: 'Privacy Notice',
                        content:
                            'This prototype uses sample data only. In the final system, user information and uploaded documents should be handled securely.',
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 4),

              _logoutButton(),
            ],
          ),
        ),
      ),
    );
  }
}