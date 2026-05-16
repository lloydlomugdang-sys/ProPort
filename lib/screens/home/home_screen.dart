import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback? onOpenPortfolio;
  final VoidCallback? onOpenCareer;
  final VoidCallback? onOpenFiles;

  const HomeScreen({
    super.key,
    this.onOpenPortfolio,
    this.onOpenCareer,
    this.onOpenFiles,
  });

  Widget _statCard({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.white, size: 24),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickActionCard({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 105,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.white, size: 28),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _taskCard({
    required bool isDone,
    required String title,
    required String subtitle,
    required String date,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isDone ? AppColors.success : AppColors.input,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isDone ? Icons.check : Icons.schedule,
              color: AppColors.white,
              size: 22,
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
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Text(
            date,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _projectPreviewCard({
    required String title,
    required String tools,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 110,
              decoration: BoxDecoration(
                color: const Color(0xFFB8CDD1),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tools,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
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
              // HEADER
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(
                      Icons.person,
                      color: AppColors.white,
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hello, User',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Build your career-ready portfolio.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // CAREER READINESS
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Career Readiness',
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          '100%',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Your portfolio profile is almost ready for career opportunities.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.all(Radius.circular(30)),
                      child: LinearProgressIndicator(
                        value: 1.0,
                        minHeight: 10,
                        backgroundColor: AppColors.darkTeal,
                        color: AppColors.white,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // STATS
              Row(
                children: [
                  _statCard(
                    icon: Icons.star_outline,
                    value: '10',
                    label: 'Skills',
                  ),
                  const SizedBox(width: 10),
                  _statCard(
                    icon: Icons.badge_outlined,
                    value: '5',
                    label: 'Certificates',
                  ),
                  const SizedBox(width: 10),
                  _statCard(
                    icon: Icons.emoji_events_outlined,
                    value: '3',
                    label: 'Achievements',
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // QUICK ACTIONS
              const Text(
                'Quick Actions',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 14),

              Row(
                children: [
                  _quickActionCard(
                    icon: Icons.add_box_outlined,
                    title: 'Add Project',
                    onTap: () {
                      onOpenPortfolio?.call();
                    },
                  ),
                  const SizedBox(width: 10),
                  _quickActionCard(
                    icon: Icons.task_alt_outlined,
                    title: 'Add Task',
                    onTap: () {
                      onOpenCareer?.call();
                    },
                  ),
                  const SizedBox(width: 10),
                  _quickActionCard(
                    icon: Icons.upload_file_outlined,
                    title: 'Upload File',
                    onTap: () {
                      onOpenFiles?.call();
                    },
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // TASKS
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Tasks',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      onOpenCareer?.call();
                    },
                    child: const Text(
                      'View all',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              _taskCard(
                isDone: true,
                title: 'Update portfolio profile',
                subtitle: 'Profile Setup',
                date: 'May 5',
              ),
              _taskCard(
                isDone: false,
                title: 'Upload resume document',
                subtitle: 'Documents',
                date: 'May 10',
              ),
              _taskCard(
                isDone: false,
                title: 'Add capstone project',
                subtitle: 'Portfolio',
                date: 'May 15',
              ),

              const SizedBox(height: 24),

              // PORTFOLIO PREVIEW
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Portfolio Preview',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      onOpenPortfolio?.call();
                    },
                    child: const Text(
                      'View all',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              Row(
                children: [
                  _projectPreviewCard(
                    title: 'Career Portfolio App',
                    tools: 'Flutter • UI Design',
                  ),
                  const SizedBox(width: 12),
                  _projectPreviewCard(
                    title: 'Resume Builder',
                    tools: 'Figma • Mobile UI',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}