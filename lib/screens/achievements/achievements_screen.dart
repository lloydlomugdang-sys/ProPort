import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import 'add_achievement_screen.dart';
import 'edit_achievement_screen.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  final List<Map<String, String>> achievements = [
    {
      'name': 'Capstone Project Contributor',
      'date': 'May 2026',
    },
    {
      'name': 'Portfolio Builder App Prototype',
      'date': 'May 2026',
    },
    {
      'name': 'Career Readiness Progress',
      'date': 'May 2026',
    },
    {
      'name': 'UI Design Improvement',
      'date': 'April 2026',
    },
  ];

  Future<void> goToAddAchievement() async {
    final newAchievement = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddAchievementScreen(),
      ),
    );

    if (!mounted) return;

    if (newAchievement != null) {
      setState(() {
        achievements.add(newAchievement);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Achievement added successfully.'),
        ),
      );
    }
  }

  Future<void> goToEditAchievement(int index) async {
    final achievement = achievements[index];

    final updatedAchievement = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => EditAchievementScreen(
          initialName: achievement['name']!,
          initialDate: achievement['date']!,
        ),
      ),
    );

    if (!mounted) return;

    if (updatedAchievement != null) {
      setState(() {
        achievements[index] = updatedAchievement;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Achievement updated successfully.'),
        ),
      );
    }
  }

  void deleteAchievement(int index) {
    setState(() {
      achievements.removeAt(index);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Achievement deleted.'),
      ),
    );
  }

  Widget _achievementCard(int index) {
    final achievement = achievements[index];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.emoji_events_outlined,
              color: AppColors.white,
              size: 23,
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  achievement['name']!,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  achievement['date']!,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          InkWell(
            onTap: () {
              goToEditAchievement(index);
            },
            borderRadius: BorderRadius.circular(8),
            child: const Icon(
              Icons.edit_outlined,
              color: AppColors.textMuted,
              size: 21,
            ),
          ),

          const SizedBox(width: 12),

          InkWell(
            onTap: () {
              deleteAchievement(index);
            },
            borderRadius: BorderRadius.circular(8),
            child: const Icon(
              Icons.delete_outline,
              color: AppColors.danger,
              size: 21,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton(
        onPressed: goToAddAchievement,
        backgroundColor: AppColors.input,
        foregroundColor: AppColors.white,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 90),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: AppColors.white,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Achievements',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              const Text(
                'Achievement List',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 14),

              if (achievements.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text(
                    'No achievements yet. Tap the + button to add one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                )
              else
                ...List.generate(
                  achievements.length,
                  (index) => _achievementCard(index),
                ),
            ],
          ),
        ),
      ),
    );
  }
}