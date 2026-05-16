import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';

class EditCertificateScreen extends StatefulWidget {
  final String initialTitle;
  final String initialDate;
  final String initialLink;
  final String initialDescription;

  const EditCertificateScreen({
    super.key,
    required this.initialTitle,
    required this.initialDate,
    required this.initialLink,
    required this.initialDescription,
  });

  @override
  State<EditCertificateScreen> createState() => _EditCertificateScreenState();
}

class _EditCertificateScreenState extends State<EditCertificateScreen> {
  late TextEditingController titleController;
  late TextEditingController dateController;
  late TextEditingController linkController;
  late TextEditingController descriptionController;

  @override
  void initState() {
    super.initState();

    titleController = TextEditingController(text: widget.initialTitle);
    dateController = TextEditingController(text: widget.initialDate);
    linkController = TextEditingController(text: widget.initialLink);
    descriptionController = TextEditingController(
      text: widget.initialDescription,
    );
  }

  @override
  void dispose() {
    titleController.dispose();
    dateController.dispose();
    linkController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  void saveChanges() {
    final title = titleController.text.trim();
    final date = dateController.text.trim();
    final link = linkController.text.trim();
    final description = descriptionController.text.trim();

    if (title.isEmpty || date.isEmpty || link.isEmpty || description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all fields.'),
        ),
      );
      return;
    }

    Navigator.pop(context, {
      'title': title,
      'date': date,
      'link': link,
      'description': description,
    });
  }

  Widget _inputField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: AppColors.black),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.grey),
            prefixIcon: Icon(icon, color: Colors.grey),
            filled: true,
            fillColor: AppColors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 18),
      ],
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
                      'Edit Certificate',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              Container(
                width: double.infinity,
                height: 170,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.badge_outlined,
                      color: AppColors.white,
                      size: 42,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Certificate Preview',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _inputField(
                      label: 'Title',
                      hint: 'Enter certificate title',
                      controller: titleController,
                      icon: Icons.badge_outlined,
                    ),
                    _inputField(
                      label: 'Date',
                      hint: 'Example: May 2026',
                      controller: dateController,
                      icon: Icons.calendar_today_outlined,
                    ),
                    _inputField(
                      label: 'Certificate Link',
                      hint: 'Enter certificate link',
                      controller: linkController,
                      icon: Icons.link,
                    ),
                    _inputField(
                      label: 'Description',
                      hint: 'Enter description',
                      controller: descriptionController,
                      icon: Icons.description_outlined,
                      maxLines: 4,
                    ),

                    const SizedBox(height: 8),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: saveChanges,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.input,
                          foregroundColor: AppColors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Save Changes',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}