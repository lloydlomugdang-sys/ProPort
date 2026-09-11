import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../constants/app_colors.dart';
import '../../services/api_client.dart';
import '../../services/document_models.dart';
import '../../services/document_scope.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/file_list_item.dart';
import '../../widgets/filter_chip_bar.dart';
import '../../widgets/grad_app_bar.dart';
import '../../widgets/search_bar_field.dart';
import 'document_ocr_screen.dart';

class ViewFilesScreen extends StatefulWidget {
  const ViewFilesScreen({
    super.key,
    required this.categoryKey,
    required this.categoryName,
    required this.folderKey,
    required this.folderName,
  });

  final String categoryKey;
  final String categoryName;
  final String folderKey;
  final String folderName;

  @override
  State<ViewFilesScreen> createState() => _ViewFilesScreenState();
}

class _ViewFilesScreenState extends State<ViewFilesScreen> {
  static const _filterOptions = ['All', 'Images', 'PDFs'];

  final _searchController = TextEditingController();
  String _query = '';
  String _filter = 'All';
  bool _loadRequested = false;
  final Set<String> _deleting = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadRequested) return;
    _loadRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await DocumentScope.of(context).load();
      } catch (_) {
        // The service exposes a safe error and keeps any previously loaded list.
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<DocumentRecord> _visibleFiles(List<DocumentRecord> documents) {
    return documents
        .where((document) {
          if (document.categoryKey != widget.categoryKey ||
              document.folderKey != widget.folderKey) {
            return false;
          }
          if (_filter == 'Images' && document.fileKind != 'image') return false;
          if (_filter == 'PDFs' && document.fileKind != 'pdf') return false;
          final query = _query.trim().toLowerCase();
          return query.isEmpty ||
              document.title.toLowerCase().contains(query) ||
              document.originalFileName.toLowerCase().contains(query) ||
              document.fileTypeLabel.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _confirmDelete(DocumentRecord document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete file?'),
        content: Text(
          'This will permanently delete “${document.originalFileName}”.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting.add(document.id));
    try {
      await DocumentScope.of(context).delete(document.id);
      if (mounted) _showSnack('File deleted.');
    } on ApiException catch (error) {
      if (mounted) _showSnack(error.message, isError: true);
    } catch (_) {
      if (mounted) {
        _showSnack(
          'Unable to delete the file. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _deleting.remove(document.id));
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: isError ? AppColors.danger : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = DocumentScope.of(context);
    final visible = _visibleFiles(service.documents);
    final title = '${widget.categoryName} • ${widget.folderName}';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: GradBackAppBar(title: title),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                SearchBarField(
                  controller: _searchController,
                  hintText: 'Search files...',
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 12),
                FilterChipBar(
                  options: _filterOptions,
                  selected: _filter,
                  onSelected: (value) => setState(() => _filter = value),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          Expanded(
            child: service.isLoading && !service.hasLoadedDocuments
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : visible.isEmpty
                ? EmptyState(
                    message: 'No files found.',
                    icon: Icons.insert_drive_file_outlined,
                    subtitle:
                        service.errorMessage ??
                        'Upload a PDF, JPG, JPEG, or PNG file to this folder.',
                  )
                : RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: () => service.load(force: true),
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, index) {
                        final document = visible[index];
                        return FileListItem(
                          fileName: document.originalFileName,
                          fileType: document.fileTypeLabel,
                          year: document.documentDate.year.toString(),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  DocumentOcrScreen(document: document),
                            ),
                          ),
                          onDelete: _deleting.contains(document.id)
                              ? null
                              : () => _confirmDelete(document),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
