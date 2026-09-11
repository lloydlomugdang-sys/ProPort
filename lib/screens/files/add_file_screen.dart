// LOCATION: lib/screens/files/add_file_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../services/api_client.dart';
import '../../services/document_models.dart';
import '../../services/document_picker.dart';
import '../../services/document_scope.dart';
import '../../services/document_service.dart';
import '../../widgets/grad_app_bar.dart';
import '../../widgets/primary_button.dart';
import 'widgets/custom_dropdown.dart';
import 'widgets/date_picker_field.dart';
import 'widgets/optional_field.dart';
import 'widgets/upload_card.dart';

class AddFileScreen extends StatefulWidget {
  const AddFileScreen({super.key, this.filePicker});

  final DocumentPicker? filePicker;

  @override
  State<AddFileScreen> createState() => _AddFileScreenState();
}

class _AddFileScreenState extends State<AddFileScreen>
    with SingleTickerProviderStateMixin {
  // ─── Upload state ─────────────────────────────────────────────────────────
  PickedDocument? _pickedFile;
  late final DocumentPicker _filePicker;

  // ─── Form state ───────────────────────────────────────────────────────────
  String? _selectedContent;
  String? _selectedFolder;
  DateTime? _selectedDate;
  bool _descriptionEnabled = false;
  bool _reflectionEnabled = false;

  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _reflectionCtrl = TextEditingController();

  bool _isSubmitting = false;

  // ─── Entrance animation ───────────────────────────────────────────────────
  late final AnimationController _entranceCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _filePicker = widget.filePicker ?? DeviceDocumentPicker();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceCtrl,
            curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
          ),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _entranceCtrl.forward();
      DocumentScope.of(context).load().catchError((_) {});
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _reflectionCtrl.dispose();
    _entranceCtrl.dispose();
    super.dispose();
  }

  // ─── Folder options derived from selected content type ────────────────────
  DocumentCategory? _selectedCategory(List<DocumentCategory> categories) {
    for (final category in categories) {
      if (category.name == _selectedContent) return category;
    }
    return null;
  }

  List<String> _folderOptions(List<DocumentCategory> categories) =>
      _selectedCategory(
        categories,
      )?.folders.map((folder) => folder.name).toList() ??
      const [];

  // ─── Upload handler ───────────────────────────────────────────────────────
  Future<void> _onUploadTap() async {
    try {
      final selected = await _filePicker.pickDocument();
      if (selected == null || !mounted) return;
      if (!selected.hasSupportedUploadType) {
        _showSnack('Please select a PDF, JPG, JPEG, or PNG file.');
        return;
      }
      if (selected.sizeBytes > DocumentService.maxUploadBytes) {
        _showSnack('The selected file exceeds the 15 MB upload limit.');
        return;
      }
      setState(() => _pickedFile = selected);
    } catch (_) {
      if (!mounted) return;
      _showSnack('Unable to read the selected file. Please try another file.');
    }
  }

  // ─── Validation + submit ──────────────────────────────────────────────────
  Future<void> _onAddFile() async {
    final file = _pickedFile;
    if (file == null) {
      _showSnack('Please select a PDF, JPG, JPEG, or PNG file.');
      return;
    }
    final service = DocumentScope.of(context);
    final category = _selectedCategory(service.categories);
    if (_selectedContent == null) {
      _showSnack('Please select a Content Type.');
      return;
    }
    if (category == null) {
      _showSnack('The selected Content Type is unavailable.');
      return;
    }
    if (_selectedFolder == null) {
      _showSnack('Please select a Folder.');
      return;
    }
    DocumentFolder? folder;
    for (final candidate in category.folders) {
      if (candidate.name == _selectedFolder) folder = candidate;
    }
    if (folder == null) {
      _showSnack('The selected Folder is unavailable.');
      return;
    }
    if (_titleCtrl.text.trim().isEmpty) {
      _showSnack('Title is required.');
      return;
    }
    if (_selectedDate == null) {
      _showSnack('Date is required.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await service.upload(
        file: file,
        categoryKey: category.key,
        folderKey: folder.key,
        title: _titleCtrl.text.trim(),
        documentDate: _selectedDate!,
        description: _descriptionEnabled ? _descriptionCtrl.text : null,
        reflection: _reflectionEnabled ? _reflectionCtrl.text : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'File uploaded successfully.',
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          duration: const Duration(seconds: 3),
        ),
      );
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      _showSnack(error.message);
    } catch (_) {
      _showSnack('Unable to upload the file. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final service = DocumentScope.of(context);
    final categoryNames = service.categories
        .map((category) => category.name)
        .toList();
    final folderOptions = _folderOptions(service.categories);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const GradBackAppBar(title: 'Add a File'),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Section 1: Upload ─────────────────────────────
                Text('1. Upload file', style: AppTextStyles.h4),
                const SizedBox(height: 10),
                UploadCard(onTap: _onUploadTap, fileName: _pickedFile?.name),

                const SizedBox(height: 24),

                // ── Section 2: Details ────────────────────────────
                Text('2. Add Details', style: AppTextStyles.h4),
                const SizedBox(height: 12),

                // Content* dropdown
                CustomDropdown(
                  label: 'Content',
                  hint: 'Select content',
                  items: categoryNames,
                  value: _selectedContent,
                  required: true,
                  onChanged: (val) {
                    setState(() {
                      _selectedContent = val;
                      _selectedFolder = null; // reset folder
                    });
                  },
                ),
                const SizedBox(height: 14),

                // Folder* dropdown — options depend on content selection
                CustomDropdown(
                  label: 'Folder',
                  hint: 'Select a folder',
                  items: folderOptions,
                  value: _selectedFolder,
                  required: true,
                  enabled: _selectedContent != null,
                  onChanged: (val) => setState(() => _selectedFolder = val),
                ),
                const SizedBox(height: 14),

                // Title*
                _buildTextField(
                  label: 'Title',
                  hint: 'Enter title',
                  controller: _titleCtrl,
                  required: true,
                ),
                const SizedBox(height: 14),

                // Date*
                DatePickerField(
                  label: 'Date',
                  selectedDate: _selectedDate,
                  required: true,
                  onDateSelected: (d) => setState(() => _selectedDate = d),
                ),
                const SizedBox(height: 14),

                // Description (optional)
                OptionalField(
                  label: 'Description',
                  hint: 'Enter description',
                  controller: _descriptionCtrl,
                  isEnabled: _descriptionEnabled,
                  onToggle: () => setState(
                    () => _descriptionEnabled = !_descriptionEnabled,
                  ),
                ),
                const SizedBox(height: 14),

                // Reflection (optional)
                OptionalField(
                  label: 'Reflection',
                  hint: 'Enter reflection',
                  controller: _reflectionCtrl,
                  isEnabled: _reflectionEnabled,
                  onToggle: () =>
                      setState(() => _reflectionEnabled = !_reflectionEnabled),
                ),

                const SizedBox(height: 28),

                // ── Add File button ───────────────────────────────
                PrimaryButton(
                  label: 'Add File',
                  icon: Icons.add_rounded,
                  onPressed: _onAddFile,
                  isLoading: _isSubmitting,
                  height: 52,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    bool required = false,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            if (required)
              Text(
                '*',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.danger,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.inputBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.poppins(
                fontSize: 14,
                color: AppColors.textMuted,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }
}
