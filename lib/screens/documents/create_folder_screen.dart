import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';

class CreateFolderScreen extends StatefulWidget {
  const CreateFolderScreen({super.key});

  @override
  State<CreateFolderScreen> createState() => _CreateFolderScreenState();
}

class _CreateFolderScreenState extends State<CreateFolderScreen> {
  final folderNameController = TextEditingController();

  String selectedCategory = 'Portfolio';
  String uploadedFileStatus = 'No file selected';

  final List<String> categories = [
    'Portfolio',
    'Certificates',
    'Resume',
    'Achievements',
  ];

  @override
  void dispose() {
    folderNameController.dispose();
    super.dispose();
  }

  void uploadFiles() {
    setState(() {
      uploadedFileStatus = 'Sample file selected';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Upload file simulation only.'),
      ),
    );
  }

  void createFolder() {
    final folderName = folderNameController.text.trim();

    if (folderName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a folder name.'),
        ),
      );
      return;
    }

    Navigator.pop(context, folderName);
  }

  Widget _inputLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.white,
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _categoryDropdown() {
    return DropdownButtonFormField<String>(
      value: selectedCategory,
      isExpanded: true,
      dropdownColor: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      menuMaxHeight: 260,
      icon: const Icon(
        Icons.keyboard_arrow_down_rounded,
        color: AppColors.white,
      ),
      style: const TextStyle(
        color: AppColors.white,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.card,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: AppColors.border,
            width: 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: AppColors.textSecondary,
            width: 1.4,
          ),
        ),
      ),
      items: categories.map((category) {
        return DropdownMenuItem<String>(
          value: category,
          child: Text(
            category,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }).toList(),
      onChanged: (value) {
        if (value == null) return;

        setState(() {
          selectedCategory = value;
        });
      },
    );
  }

  Widget _folderNameInput() {
    return TextField(
      controller: folderNameController,
      style: const TextStyle(
        color: AppColors.black,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        hintText: 'Enter folder name',
        hintStyle: const TextStyle(color: Colors.grey),
        prefixIcon: const Icon(
          Icons.folder_outlined,
          color: Colors.grey,
        ),
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _fileStatusBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.insert_drive_file_outlined,
            color: AppColors.white,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              uploadedFileStatus,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filledButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color backgroundColor = AppColors.input,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: AppColors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _cancelButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
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
        child: const Text(
          'Cancel',
          style: TextStyle(
            fontWeight: FontWeight.bold,
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
                      'Create Folder',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 26),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Folder Information',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 20),

                    _inputLabel('Category'),

                    const SizedBox(height: 8),

                    _categoryDropdown(),

                    const SizedBox(height: 18),

                    _inputLabel('Folder Name'),

                    const SizedBox(height: 8),

                    _folderNameInput(),

                    const SizedBox(height: 18),

                    _fileStatusBox(),

                    const SizedBox(height: 22),

                    _filledButton(
                      icon: Icons.upload_file_outlined,
                      label: 'Upload Files',
                      backgroundColor: AppColors.darkTeal,
                      onPressed: uploadFiles,
                    ),

                    const SizedBox(height: 12),

                    _filledButton(
                      icon: Icons.create_new_folder_outlined,
                      label: 'Create Folder',
                      onPressed: createFolder,
                    ),

                    const SizedBox(height: 12),

                    _cancelButton(),
                  ],
                ),
              ),

              const SizedBox(height: 20),

             
            ],
          ),
        ),
      ),
    );
  }
}