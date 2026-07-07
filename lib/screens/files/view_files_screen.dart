// LOCATION: lib/screens/files/view_files_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../constants/app_colors.dart';
import '../../widgets/grad_app_bar.dart';
import '../../widgets/filter_chip_bar.dart';
import '../../widgets/search_bar_field.dart';
import '../../widgets/file_list_item.dart';
import '../../widgets/empty_state.dart';

class ViewFilesScreen extends StatefulWidget {
  const ViewFilesScreen({
    super.key,
    required this.categoryName,
    required this.folderName,
  });

  final String categoryName;
  final String folderName;

  @override
  State<ViewFilesScreen> createState() => _ViewFilesScreenState();
}

class _ViewFilesScreenState extends State<ViewFilesScreen> {
  final _searchCtrl = TextEditingController();

  String _query = '';
  String _filter = 'All';

  static const List<String> _filterOptions = [
    'All',
    'Images',
    'PDFs',
    'Other',
  ];

  final List<_FileItem> _files = [
    _FileItem(
      name: 'Life After Graduation: The Reality No One Talks About',
      fileName: 'Life_After_Graduation.pdf',
      fileType: 'PDF',
      year: '2026',
    ),
    _FileItem(
      name: 'Agentic Coding',
      fileName: 'Agentic_Coding.png',
      fileType: 'Image',
      year: '2025',
    ),
    _FileItem(
      name: 'Career Development Workshop',
      fileName: 'Career_Workshop.pdf',
      fileType: 'PDF',
      year: '2025',
    ),
    _FileItem(
      name: 'Internship Certificate',
      fileName: 'Internship_Cert.jpg',
      fileType: 'Image',
      year: '2026',
    ),
    _FileItem(
      name: 'Portfolio Design Document',
      fileName: 'Portfolio_Design.docx',
      fileType: 'Other',
      year: '2026',
    ),
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_FileItem> get _filteredFiles {
    var list = List<_FileItem>.from(_files);

    if (_filter != 'All') {
      list = list.where((f) {
        if (_filter == 'Images') return f.fileType == 'Image';
        if (_filter == 'PDFs') return f.fileType == 'PDF';
        return f.fileType == 'Other';
      }).toList();
    }

    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();

      list = list.where((f) {
        return f.name.toLowerCase().contains(q) ||
            f.fileName.toLowerCase().contains(q) ||
            f.fileType.toLowerCase().contains(q);
      }).toList();
    }

    return list;
  }

  void _deleteFile(_FileItem file) {
    setState(() => _files.remove(file));
    _showSnack('File deleted.');
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = '${widget.categoryName} • ${widget.folderName}';
    final visible = _filteredFiles;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: GradBackAppBar(
        title: title,
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                // Search Bar (Always Visible)
                SearchBarField(
                  controller: _searchCtrl,
                  hintText: 'Search files...',
                  onChanged: (v) => setState(() => _query = v),
                ),

                const SizedBox(height: 12),

                // Filter Chips
                FilterChipBar(
                  options: _filterOptions,
                  selected: _filter,
                  onSelected: (v) => setState(() => _filter = v),
                ),
              ],
            ),
          ),
          const Divider(
            height: 1,
            color: AppColors.divider,
          ),
          Expanded(
            child: visible.isEmpty
                ? const EmptyState(
                    message: 'No files found.',
                    icon: Icons.insert_drive_file_outlined,
                    subtitle: 'Try a different filter or search term.',
                  )
                : ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final file = visible[i];

                      return FileListItem(
                        fileName: file.fileName,
                        fileType: file.fileType,
                        year: file.year,
                        onTap: () =>
                            _showSnack('Opened: ${file.name}'),
                        onDelete: () => _deleteFile(file),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _FileItem {
  const _FileItem({
    required this.name,
    required this.fileName,
    required this.fileType,
    required this.year,
  });

  final String name;
  final String fileName;
  final String fileType;
  final String year;
}