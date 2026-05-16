import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import 'edit_project_screen.dart';

class ProjectDetailsScreen extends StatefulWidget {
  final String title;
  final String tools;
  final String description;

  const ProjectDetailsScreen({
    super.key,
    required this.title,
    required this.tools,
    required this.description,
  });

  @override
  State<ProjectDetailsScreen> createState() => _ProjectDetailsScreenState();
}

class _ProjectDetailsScreenState extends State<ProjectDetailsScreen> {
  late String projectTitle;
  late String projectTools;
  late String projectDescription;

  @override
  void initState() {
    super.initState();

    projectTitle = widget.title;
    projectTools = widget.tools;
    projectDescription = widget.description;
  }

  Future<void> goToEditProject() async {
    final updatedProject = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProjectScreen(
          initialTitle: projectTitle,
          initialTools: projectTools,
          initialDescription: projectDescription,
        ),
      ),
    );

    if (updatedProject != null) {
      setState(() {
        projectTitle = updatedProject['title']!;
        projectTools = updatedProject['tools']!;
        projectDescription = updatedProject['description']!;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Project updated successfully.'),
        ),
      );
    }
  }

  Widget _detailBox({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.white, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 14,
                    height: 1.4,
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

  Widget _projectPreviewImage() {
    return Container(
      height: 210,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFB8CDD1),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Icon(
        Icons.image_outlined,
        color: AppColors.input,
        size: 64,
      ),
    );
  }

  Widget _editButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: goToEditProject,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Edit Project'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.input,
          foregroundColor: AppColors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
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
                      'Project Details',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              _projectPreviewImage(),

              const SizedBox(height: 22),

              Text(
                projectTitle,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                projectTools,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 24),

              _detailBox(
                icon: Icons.description_outlined,
                label: 'Description',
                value: projectDescription,
              ),

              _detailBox(
                icon: Icons.handyman_outlined,
                label: 'Tools Used',
                value: projectTools,
              ),

              _detailBox(
                icon: Icons.calendar_today_outlined,
                label: 'Date Added',
                value: 'May 2026',
              ),

              const SizedBox(height: 18),

              _editButton(),
            ],
          ),
        ),
      ),
    );
  }
}