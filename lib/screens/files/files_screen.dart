import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../services/document_models.dart';
import '../../services/document_scope.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/folder_row_item.dart';
import '../../widgets/grad_app_bar.dart';
import '../../widgets/search_bar_field.dart';
import 'view_files_screen.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({
    super.key,
    this.initialCategoryKey,
    this.initialFolderKey,
  });
  final String? initialCategoryKey;
  final String? initialFolderKey;

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _loadRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadRequested) return;
    _loadRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    try {
      await DocumentScope.of(context).load(force: force);
    } catch (_) {
      // The service exposes the safe API error in this screen's error state.
    }
  }

  List<DocumentCategory> _filtered(List<DocumentCategory> categories) {
    if (_query.trim().isEmpty) return categories;
    final query = _query.toLowerCase();
    return categories
        .map(
          (category) => DocumentCategory(
            key: category.key,
            name: category.name,
            folders: category.folders
                .where((folder) => folder.name.toLowerCase().contains(query))
                .toList(growable: false),
          ),
        )
        .where(
          (category) =>
              category.folders.isNotEmpty ||
              category.name.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  void _openFolder(DocumentCategory category, DocumentFolder folder) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ViewFilesScreen(
          categoryKey: category.key,
          categoryName: category.name,
          folderKey: folder.key,
          folderName: folder.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = DocumentScope.of(context);
    final categoryKey = widget.initialCategoryKey;
    if (categoryKey != null || widget.initialFolderKey != null) {
      final matches = service.categories.where(
        (item) => item.key == categoryKey,
      );
      return ViewFilesScreen(
        categoryKey: categoryKey,
        folderKey: widget.initialFolderKey,
        categoryName: categoryKey == null
            ? 'Creative Titles'
            : matches.isEmpty
            ? 'Files'
            : matches.first.name,
      );
    }
    final categories = _filtered(service.categories);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const GradAppBar(title: 'Files'),
      body: service.isLoading && service.categories.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : service.errorMessage != null && service.categories.isEmpty
          ? _LoadError(
              message: service.errorMessage!,
              onRetry: () => _load(force: true),
            )
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () => _load(force: true),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SearchBarField(
                      controller: _searchController,
                      hintText: 'Search folders...',
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: 20),
                    if (categories.isEmpty)
                      const EmptyState(
                        message: 'No folders found.',
                        icon: Icons.folder_off_outlined,
                      )
                    else
                      ...categories.map(
                        (category) => _CategorySection(
                          category: category,
                          countForFolder: (folder) => service.summary
                              .folderCount(category.key, folder.key),
                          onFolderTap: (folder) =>
                              _openFolder(category, folder),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.category,
    required this.countForFolder,
    required this.onFolderTap,
  });

  final DocumentCategory category;
  final int Function(DocumentFolder folder) countForFolder;
  final ValueChanged<DocumentFolder> onFolderTap;

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
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: category.folders.asMap().entries.map((entry) {
                final folder = entry.value;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: FolderRowItem(
                        name: folder.name,
                        count: countForFolder(folder),
                        onTap: () => onFolderTap(folder),
                      ),
                    ),
                    if (entry.key < category.folders.length - 1)
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

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              color: AppColors.textMuted,
              size: 42,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Try Again')),
          ],
        ),
      ),
    );
  }
}
