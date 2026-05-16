import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import 'document_viewer_screen.dart';

class DocumentFilesScreen extends StatefulWidget {
  final String folderName;

  const DocumentFilesScreen({
    super.key,
    required this.folderName,
  });

  @override
  State<DocumentFilesScreen> createState() => _DocumentFilesScreenState();
}

class _DocumentFilesScreenState extends State<DocumentFilesScreen> {
  final TextEditingController searchController = TextEditingController();

  final List<Map<String, String>> files = [
    {
      'name': 'Resume.pdf',
      'type': 'PDF Document',
      'date': 'May 2026',
      'description': 'A resume document prepared for internship applications.',
    },
    {
      'name': 'Certificate.png',
      'type': 'Image File',
      'date': 'April 2026',
      'description': 'A sample certificate uploaded for portfolio records.',
    },
    {
      'name': 'Project_Output.docx',
      'type': 'Word Document',
      'date': 'March 2026',
      'description': 'A project output document included in the portfolio.',
    },
    {
      'name': 'Portfolio_Design.png',
      'type': 'Image File',
      'date': 'May 2026',
      'description': 'A portfolio design preview for the ProPort application.',
    },
    {
      'name': 'Career_Plan.pdf',
      'type': 'PDF Document',
      'date': 'May 2026',
      'description': 'A career preparation plan for student development.',
    },
  ];

  String searchText = '';

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<Map<String, String>> get filteredFiles {
    final query = searchText.toLowerCase();

    if (query.isEmpty) {
      return files;
    }

    return files.where((file) {
      final fileName = file['name']!.toLowerCase();
      final fileType = file['type']!.toLowerCase();

      return fileName.contains(query) || fileType.contains(query);
    }).toList();
  }

  IconData _getFileIcon(String fileName) {
    final lowerName = fileName.toLowerCase();

    if (lowerName.endsWith('.pdf')) {
      return Icons.picture_as_pdf_outlined;
    } else if (lowerName.endsWith('.png') ||
        lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg')) {
      return Icons.image_outlined;
    } else if (lowerName.endsWith('.doc') || lowerName.endsWith('.docx')) {
      return Icons.article_outlined;
    }

    return Icons.description_outlined;
  }

  Future<void> showUploadDialog() async {
    final nameController = TextEditingController();
    final typeController = TextEditingController();
    final descriptionController = TextEditingController();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Upload File',
            style: TextStyle(
              color: AppColors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: AppColors.black),
                  decoration: InputDecoration(
                    hintText: 'File name',
                    hintStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: AppColors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: typeController,
                  style: const TextStyle(color: AppColors.black),
                  decoration: InputDecoration(
                    hintText: 'File type',
                    hintStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: AppColors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  maxLines: 3,
                  style: const TextStyle(color: AppColors.black),
                  decoration: InputDecoration(
                    hintText: 'Description',
                    hintStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: AppColors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                final type = typeController.text.trim();
                final description = descriptionController.text.trim();

                if (name.isEmpty || type.isEmpty || description.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please complete all file fields.'),
                    ),
                  );
                  return;
                }

                Navigator.pop(context, {
                  'name': name,
                  'type': type,
                  'date': 'May 2026',
                  'description': description,
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.input,
                foregroundColor: AppColors.white,
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    typeController.dispose();
    descriptionController.dispose();

    if (result != null) {
      setState(() {
        files.add(result);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File uploaded successfully.'),
        ),
      );
    }
  }

  void deleteFile(int index) {
    final fileToRemove = filteredFiles[index];

    setState(() {
      files.remove(fileToRemove);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('File deleted.'),
      ),
    );
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
        hintText: 'Search file name',
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

  Widget _fileCard({
    required int index,
    required String name,
    required String type,
    required String date,
    required String description,
  }) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DocumentViewerScreen(
              fileName: name,
              fileType: type,
              fileDate: date,
              description: description,
            ),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.input,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _getFileIcon(name),
                        color: AppColors.white,
                        size: 42,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    name,
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
                    type,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                  deleteFile(index);
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

  @override
  Widget build(BuildContext context) {
    final visibleFiles = filteredFiles;

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton(
        onPressed: showUploadDialog,
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
                      'Documents',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.folderName,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${files.length} file(s) inside this folder',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              const Text(
                'Folder Name',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              _searchBar(),

              const SizedBox(height: 22),

              if (visibleFiles.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text(
                    'No files found.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                )
              else
                GridView.builder(
                  itemCount: visibleFiles.length,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.82,
                  ),
                  itemBuilder: (context, index) {
                    final file = visibleFiles[index];

                    return _fileCard(
                      index: index,
                      name: file['name']!,
                      type: file['type']!,
                      date: file['date']!,
                      description: file['description']!,
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}