// LOCATION: lib/screens/files/files_screen.dart
//
// Create the folder:  lib/screens/files/
// Then place this file inside it.

import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/grad_app_bar.dart';
import '../../widgets/search_bar_field.dart';
import '../../widgets/folder_row_item.dart';
import '../../widgets/empty_state.dart';
import 'view_files_screen.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  final List<_FolderCategory> _categories = [
    _FolderCategory(
      name: 'Curriculum Vitae',
      folders: [
        _Folder('Creative Title', 1),
        _Folder('Curriculum Vitae', 0),
      ],
    ),
    _FolderCategory(
      name: 'Scholastic Record',
      folders: [
        _Folder('Creative Title', 1),
        _Folder('Unofficial TOR with Reflections', 4),
      ],
    ),
    _FolderCategory(
      name: 'Certificates',
      folders: [
        _Folder('Creative Title', 1),
        _Folder('Seminars', 6),
        _Folder('Other Seminars', 2),
        _Folder('Trainings', 3),
      ],
    ),
    _FolderCategory(
      name: 'Accomplishments',
      folders: [
        _Folder('Creative Title', 1),
        _Folder('Thesis/Capstone', 1),
        _Folder('Case Studies', 4),
        _Folder('Projects', 5),
        _Folder('Assessments', 20),
      ],
    ),
    _FolderCategory(
      name: 'Other Achievements',
      folders: [
        _Folder('Creative Title', 1),
        _Folder('Projects', 2),
      ],
    ),
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_FolderCategory> get _filtered {
    if (_query.isEmpty) return _categories;
    final q = _query.toLowerCase();
    return _categories
        .map((cat) => _FolderCategory(
              name: cat.name,
              folders: cat.folders
                  .where((f) => f.name.toLowerCase().contains(q))
                  .toList(),
            ))
        .where((cat) =>
            cat.folders.isNotEmpty ||
            cat.name.toLowerCase().contains(q))
        .toList();
  }

  void _openFolder(String categoryName, _Folder folder) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ViewFilesScreen(
          categoryName: categoryName,
          folderName: folder.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const GradAppBar(title: 'Files'),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SearchBarField(
              controller: _searchCtrl,
              hintText: 'Search folders...',
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 20),
            if (filtered.isEmpty)
              const EmptyState(
                message: 'No folders found.',
                icon: Icons.folder_off_outlined,
              )
            else
              ...filtered.map(
                (cat) => _CategorySection(
                  category: cat,
                  onFolderTap: (folder) =>
                      _openFolder(cat.name, folder),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.category,
    required this.onFolderTap,
  });

  final _FolderCategory category;
  final ValueChanged<_Folder> onFolderTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Text(
              category.name,
              style: AppTextStyles.h4.copyWith(color: AppColors.primary),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: category.folders.asMap().entries.map((entry) {
                final idx    = entry.key;
                final folder = entry.value;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: FolderRowItem(
                        name: folder.name,
                        count: folder.count,
                        onTap: () => onFolderTap(folder),
                      ),
                    ),
                    if (idx < category.folders.length - 1)
                      const Divider(
                        height: 1,
                        indent: 14,
                        endIndent: 14,
                        color: AppColors.divider,
                      ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderCategory {
  const _FolderCategory({required this.name, required this.folders});
  final String name;
  final List<_Folder> folders;
}

class _Folder {
  const _Folder(this.name, this.count);
  final String name;
  final int count;
}