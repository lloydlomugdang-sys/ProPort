import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import 'add_skill_screen.dart';
import 'edit_skill_screen.dart';

class SkillsScreen extends StatefulWidget {
  const SkillsScreen({super.key});

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  final List<Map<String, String>> skills = [
    {
      'name': 'Flutter Development',
      'level': 'Intermediate',
    },
    {
      'name': 'UI/UX Design',
      'level': 'Intermediate',
    },
    {
      'name': 'Database Management',
      'level': 'Beginner',
    },
    {
      'name': 'Mobile App Prototyping',
      'level': 'Intermediate',
    },
  ];

  Future<void> goToAddSkill() async {
    final newSkill = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddSkillScreen(),
      ),
    );

    if (!mounted) return;

    if (newSkill != null) {
      setState(() {
        skills.add(newSkill);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Skill added successfully.'),
        ),
      );
    }
  }

  Future<void> goToEditSkill(int index) async {
    final skill = skills[index];

    final updatedSkill = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => EditSkillScreen(
          initialName: skill['name']!,
          initialLevel: skill['level']!,
        ),
      ),
    );

    if (!mounted) return;

    if (updatedSkill != null) {
      setState(() {
        skills[index] = updatedSkill;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Skill updated successfully.'),
        ),
      );
    }
  }

  void deleteSkill(int index) {
    setState(() {
      skills.removeAt(index);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Skill deleted.'),
      ),
    );
  }

  Widget _skillCard(int index) {
    final skill = skills[index];

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
              Icons.star_outline,
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
                  skill['name']!,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  skill['level']!,
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
              goToEditSkill(index);
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
              deleteSkill(index);
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
        onPressed: goToAddSkill,
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
                      'Skills',
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
                'Skill List',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 14),

              if (skills.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text(
                    'No skills yet. Tap the + button to add one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                )
              else
                ...List.generate(
                  skills.length,
                  (index) => _skillCard(index),
                ),
            ],
          ),
        ),
      ),
    );
  }
}