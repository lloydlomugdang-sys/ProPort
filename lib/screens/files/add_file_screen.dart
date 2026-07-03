// LOCATION: lib/screens/files/add_file_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/grad_app_bar.dart';
import '../../widgets/primary_button.dart';
import 'models/added_file_model.dart';
import 'widgets/upload_card.dart';
import 'widgets/custom_dropdown.dart';
import 'widgets/date_picker_field.dart';
import 'widgets/optional_field.dart';
import 'package:image_picker/image_picker.dart';

class AddFileScreen extends StatefulWidget {
  const AddFileScreen({super.key});

  @override
  State<AddFileScreen> createState() => _AddFileScreenState();
}

class _AddFileScreenState extends State<AddFileScreen>
    with SingleTickerProviderStateMixin {
  // ─── Upload state ─────────────────────────────────────────────────────────
  String? _pickedFileName;
  String? _pickedFilePath;

  // ─── Form state ───────────────────────────────────────────────────────────
  String? _selectedContent;
  String? _selectedFolder;
  DateTime? _selectedDate;
  bool _descriptionEnabled = false;
  bool _reflectionEnabled  = false;

  final _titleCtrl       = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _reflectionCtrl  = TextEditingController();

  bool _isSubmitting = false;

  // ─── Entrance animation ───────────────────────────────────────────────────
  late final AnimationController _entranceCtrl;
  late final Animation<double>   _fadeAnim;
  late final Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entranceCtrl.forward();
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
  List<String> get _folderOptions =>
      _selectedContent != null
          ? (kFoldersByContent[_selectedContent] ?? [])
          : [];

  // ─── Upload handler ───────────────────────────────────────────────────────
  Future<void> _onUploadTap() async {
    // Try using image_picker (already in pubspec).
    // For a real file picker add file_picker package later.
    try {
      final picker = ImagePicker();
      final result = await picker.pickImage(source: ImageSource.gallery);
      if (result != null && mounted) {
        setState(() {
          _pickedFileName = result.name;
          _pickedFilePath = result.path;
        });
      }
    } catch (_) {
      if (!mounted) return;
      _showInfo(
        'File Picker',
        'File picker integration will be connected in the next implementation phase.',
      );
    }
  }

  // ─── Validation + submit ──────────────────────────────────────────────────
  Future<void> _onAddFile() async {
    if (_selectedContent == null) {
      _showSnack('Please select a Content Type.');
      return;
    }
    if (_selectedFolder == null) {
      _showSnack('Please select a Folder.');
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
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    // Store in temporary in-memory store
    // TODO: replace with MongoDB call
    addedFileStore.addFile(AddedFile(
      id:          DateTime.now().millisecondsSinceEpoch.toString(),
      fileName:    _pickedFileName ?? '${_titleCtrl.text.trim()}.file',
      contentType: _selectedContent!,
      folder:      _selectedFolder!,
      title:       _titleCtrl.text.trim(),
      date:        _selectedDate!,
      description: _descriptionEnabled ? _descriptionCtrl.text.trim() : null,
      reflection:  _reflectionEnabled  ? _reflectionCtrl.text.trim()  : null,
      filePath:    _pickedFilePath,
    ));

    setState(() => _isSubmitting = false);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        'File added successfully (Development Mode)',
        style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
      ),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      duration: const Duration(seconds: 3),
    ));

    Navigator.pop(context);
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white)),
      backgroundColor: AppColors.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      duration: const Duration(seconds: 3),
    ));
  }

  void _showInfo(String title, String content) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: AppTextStyles.h3),
        content: Text(content,
            style: AppTextStyles.bodySmall.copyWith(height: 1.6)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK',
                style: AppTextStyles.labelLarge
                    .copyWith(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
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
                UploadCard(
                  onTap: _onUploadTap,
                  fileName: _pickedFileName,
                  filePath: _pickedFilePath,
                ),

                const SizedBox(height: 24),

                // ── Section 2: Details ────────────────────────────
                Text('2. Add Details', style: AppTextStyles.h4),
                const SizedBox(height: 12),

                // Content* dropdown
                CustomDropdown(
                  label: 'Content',
                  hint: 'Select content',
                  items: kContentTypes,
                  value: _selectedContent,
                  required: true,
                  onChanged: (val) {
                    setState(() {
                      _selectedContent = val;
                      _selectedFolder  = null; // reset folder
                    });
                  },
                ),
                const SizedBox(height: 14),

                // Folder* dropdown — options depend on content selection
                CustomDropdown(
                  label: 'Folder',
                  hint: 'Select a folder',
                  items: _folderOptions,
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
                      () => _descriptionEnabled = !_descriptionEnabled),
                ),
                const SizedBox(height: 14),

                // Reflection (optional)
                OptionalField(
                  label: 'Reflection',
                  hint: 'Enter reflection',
                  controller: _reflectionCtrl,
                  isEnabled: _reflectionEnabled,
                  onToggle: () => setState(
                      () => _reflectionEnabled = !_reflectionEnabled),
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
            Text(label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                )),
            if (required)
              Text('*',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.danger,
                  )),
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
                fontSize: 14, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.poppins(
                  fontSize: 14, color: AppColors.textMuted),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 13),
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