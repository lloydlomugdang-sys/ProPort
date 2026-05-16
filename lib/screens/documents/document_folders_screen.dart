import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import 'create_folder_screen.dart';
import 'document_files_screen.dart';

class DocumentFoldersScreen extends StatefulWidget {
  const DocumentFoldersScreen({super.key});

  @override
  State<DocumentFoldersScreen> createState() => _DocumentFoldersScreenState();
}

class _DocumentFoldersScreenState extends State<DocumentFoldersScreen> {
  final TextEditingController searchController = TextEditingController();

  final Map<String, List<Map<String, String>>> folderCategories = {
    'Portfolio': [
      {'name': 'Projects', 'count': '4 files'},
      {'name': 'App Designs', 'count': '2 files'},
      {'name': 'Outputs', 'count': '3 files'},
    ],
    'Certificates': [
      {'name': 'Seminars', 'count': '2 files'},
      {'name': 'Training', 'count': '1 file'},
      {'name': 'Awards', 'count': '3 files'},
    ],
  };

  String searchText = '';

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> goToCreateFolder() async {
    final folderName = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const CreateFolderScreen(),
      ),
    );

    if (folderName != null && folderName.trim().isNotEmpty) {
      setState(() {
        folderCategories['Portfolio']!.add({
          'name': folderName.trim(),
          'count': '0 files',
        });
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Folder created successfully.'),
        ),
      );
    }
  }

  void deleteFolder(String category, int index) {
    setState(() {
      folderCategories[category]!.removeAt(index);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Folder deleted.'),
      ),
    );
  }

  List<MapEntry<String, List<Map<String, String>>>> getFilteredCategories() {
    final query = searchText.toLowerCase();

    return folderCategories.entries
        .map((entry) {
          final filteredFolders = entry.value.where((folder) {
            final name = folder['name']!.toLowerCase();
            return name.contains(query);
          }).toList();

          return MapEntry(entry.key, filteredFolders);
        })
        .where((entry) => entry.value.isNotEmpty)
        .toList();
  }

  Widget _searchBar() {
    return TextField(
      controller: searchController,
      onChanged: (value) {
        setState(() {
          searchText = value;
        });
      },
      style: const TextStyle(
        color: AppColors.black,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        hintText: 'Search folders',
        hintStyle: const TextStyle(
          color: Colors.grey,
          fontSize: 14,
        ),
        prefixIcon: const Icon(
          Icons.search,
          color: Colors.grey,
        ),
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _folderCard({
    required String category,
    required int index,
    required String name,
    required String count,
  }) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DocumentFilesScreen(folderName: name),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: double.infinity,
                    height: 70,
                    decoration: BoxDecoration(
                      color: AppColors.input,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.folder_outlined,
                      color: AppColors.white,
                      size: 42,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    count,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),

            Positioned(
              top: 6,
              right: 6,
              child: InkWell(
                onTap: () {
                  deleteFolder(category, index);
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.close,
                    color: AppColors.textSecondary,
                    size: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categorySection({
    required String category,
    required List<Map<String, String>> folders,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            category,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 14),

          GridView.builder(
            itemCount: folders.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.90,
            ),
            itemBuilder: (context, index) {
              final folder = folders[index];

              return _folderCard(
                category: category,
                index: folderCategories[category]!.indexOf(folder),
                name: folder['name']!,
                count: folder['count']!,
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredCategories = getFilteredCategories();

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton(
        onPressed: goToCreateFolder,
        backgroundColor: AppColors.input,
        foregroundColor: AppColors.white,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Documents',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 6),

              const Text(
                'Organize your portfolio files and certificates.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                'Folders',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              _searchBar(),

              const SizedBox(height: 22),

              if (filteredCategories.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text(
                    'No folders found.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                )
              else
                ...filteredCategories.map(
                  (entry) => _categorySection(
                    category: entry.key,
                    folders: entry.value,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}