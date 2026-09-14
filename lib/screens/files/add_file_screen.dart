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

enum _OcrField { content, folder, title, date, description }

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
  bool _isSuggesting = false;
  DocumentMetadataSuggestions? _suggestions;
  String? _suggestionMessage;
  int _previewOperation = 0;
  final Set<_OcrField> _automaticFields = {};
  final Set<_OcrField> _manualFields = {};
  bool _hasEditedAiSuggestion = false;
  bool _writingSuggestions = false;
  bool _suggestionFailed = false;
  bool _suggestedByAi = false;
  String _observedTitle = '';
  String _observedDescription = '';

  // ─── Entrance animation ───────────────────────────────────────────────────
  late final AnimationController _entranceCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _filePicker = widget.filePicker ?? DeviceDocumentPicker();
    _titleCtrl.addListener(() {
      if (_titleCtrl.text == _observedTitle) return;
      _observedTitle = _titleCtrl.text;
      if (!_writingSuggestions) {
        setState(() => _markManual(_OcrField.title));
      }
    });
    _descriptionCtrl.addListener(() {
      if (_descriptionCtrl.text == _observedDescription) return;
      _observedDescription = _descriptionCtrl.text;
      if (!_writingSuggestions) {
        setState(() => _markManual(_OcrField.description));
      }
    });
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Categories can finish loading after the OCR response. Apply matching keys
    // then as well, without letting a category-list failure discard useful text.
    final operation = _previewOperation;
    if (_suggestions != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && operation == _previewOperation) _applySuggestions();
      });
    }
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
    if (_isSubmitting) return;
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
      setState(() {
        _clearAutomaticFields();
        _pickedFile = selected;
        _previewOperation++;
        _isSuggesting = false;
        _suggestions = null;
        _suggestionMessage = null;
        _suggestionFailed = false;
        _suggestedByAi = false;
        _hasEditedAiSuggestion = false;
      });
      await _suggestDetails();
    } catch (_) {
      if (!mounted) return;
      _showSnack('Unable to read the selected file. Please try another file.');
    }
  }

  // ─── Validation + submit ──────────────────────────────────────────────────
  Future<void> _onAddFile() async {
    if (_isSubmitting) return;
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

    setState(() {
      _isSubmitting = true;
      _isSuggesting = false;
    });
    _previewOperation++;
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

  Future<void> _suggestDetails() async {
    final file = _pickedFile;
    if (file == null || _isSuggesting || _isSubmitting) return;
    final operation = ++_previewOperation;
    final service = DocumentScope.of(context);
    setState(() {
      _isSuggesting = true;
      _suggestionMessage = null;
      _suggestionFailed = false;
    });
    try {
      final result = await service.previewOcr(file);
      if (!mounted || operation != _previewOperation) return;
      if (!result.isReady) {
        throw const ApiException(
          code: 'OCR_FAILED',
          message: 'Automatic reading failed.',
        );
      }
      final suggestions = result.isReady ? result.metadataSuggestions : null;
      setState(() {
        _suggestions = suggestions;
        _suggestedByAi = result.metadataAnalysis?.source == 'gemini';
        _suggestionMessage = suggestions == null || suggestions.isEmpty
            ? 'No reliable details found. You can enter them manually.'
            : 'Suggested from OCR — review before adding your file.';
        if (_suggestedByAi) {
          _suggestionMessage =
              'AI suggested from document — review and edit before saving.';
        } else if (result.metadataAnalysis?.aiStatus == 'unavailable') {
          _suggestionMessage = suggestions == null || suggestions.isEmpty
              ? 'AI suggestions are temporarily unavailable. You can enter the details manually.'
              : 'AI suggestions are temporarily unavailable. Basic document details were applied where possible.';
        }
      });
      if (suggestions != null) _applySuggestions();
    } on ApiException catch (error) {
      if (mounted && operation == _previewOperation) {
        setState(() {
          _suggestionFailed = true;
          _suggestionMessage = switch (error.code) {
            'NETWORK_ERROR' =>
              'No connection for automatic reading. You can still enter the details manually.',
            'NETWORK_TIMEOUT' =>
              'Automatic reading took too long. You can still enter the details manually.',
            'RATE_LIMITED' =>
              'Too many reading requests. Please wait before retrying, or enter the details manually.',
            _ =>
              "We couldn't automatically read this file. You can still enter the details manually.",
          };
        });
      }
    } catch (_) {
      if (mounted && operation == _previewOperation) {
        setState(() {
          _suggestionFailed = true;
          _suggestionMessage =
              "We couldn't automatically read this file. You can still enter the details manually.";
        });
      }
    } finally {
      if (mounted && operation == _previewOperation) {
        setState(() => _isSuggesting = false);
      }
    }
  }

  void _markManual(_OcrField field) {
    if (_suggestedByAi && _automaticFields.contains(field)) {
      _hasEditedAiSuggestion = true;
    }
    _automaticFields.remove(field);
    _manualFields.add(field);
  }

  void _clearAutomaticFields() {
    _writingSuggestions = true;
    try {
      if (_automaticFields.contains(_OcrField.content)) _selectedContent = null;
      if (_automaticFields.contains(_OcrField.folder)) _selectedFolder = null;
      if (_automaticFields.contains(_OcrField.title)) _titleCtrl.clear();
      if (_automaticFields.contains(_OcrField.date)) _selectedDate = null;
      if (_automaticFields.contains(_OcrField.description)) {
        _descriptionCtrl.clear();
        _descriptionEnabled = false;
      }
      _automaticFields.clear();
    } finally {
      _writingSuggestions = false;
    }
  }

  void _applySuggestions({bool replace = false}) {
    final suggestions = _suggestions;
    if (suggestions == null || _isSubmitting) return;
    final categories = DocumentScope.of(context).categories;
    _writingSuggestions = true;
    try {
      setState(() {
        final suggestedCategory = categories
            .where((category) => category.key == suggestions.categoryKey)
            .firstOrNull;
        if (suggestedCategory != null &&
            (replace ||
                (!_manualFields.contains(_OcrField.content) &&
                    _selectedContent == null))) {
          if (_selectedContent != suggestedCategory.name) {
            _selectedFolder = null;
          }
          _selectedContent = suggestedCategory.name;
          _automaticFields.add(_OcrField.content);
        }
        final category = _selectedCategory(categories);
        if (category != null &&
            category.key == suggestions.categoryKey &&
            (replace ||
                (!_manualFields.contains(_OcrField.folder) &&
                    _selectedFolder == null))) {
          final folder = category.folders
              .where((folder) => folder.key == suggestions.folderKey)
              .firstOrNull;
          if (folder != null) {
            _selectedFolder = folder.name;
            _automaticFields.add(_OcrField.folder);
          }
        }
        if (suggestions.title != null &&
            (replace ||
                (!_manualFields.contains(_OcrField.title) &&
                    _titleCtrl.text.trim().isEmpty))) {
          _titleCtrl.text = suggestions.title!;
          _automaticFields.add(_OcrField.title);
        }
        if (suggestions.documentDate != null &&
            (replace ||
                (!_manualFields.contains(_OcrField.date) &&
                    _selectedDate == null))) {
          _selectedDate = suggestions.documentDate;
          _automaticFields.add(_OcrField.date);
        }
        if (suggestions.description != null &&
            (replace ||
                (!_manualFields.contains(_OcrField.description) &&
                    _descriptionCtrl.text.trim().isEmpty))) {
          _descriptionCtrl.text = suggestions.description!;
          _descriptionEnabled = true;
          _automaticFields.add(_OcrField.description);
        }
        if (replace) {
          _manualFields.removeAll(_automaticFields);
          _hasEditedAiSuggestion = false;
        }
      });
    } finally {
      _writingSuggestions = false;
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

                if (_pickedFile != null) ...[
                  if (_isSuggesting)
                    const Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('Reading document...'),
                      ],
                    ),
                  if (_suggestionFailed)
                    TextButton.icon(
                      onPressed: _isSubmitting ? null : _suggestDetails,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retry automatic reading'),
                    ),
                  if (_suggestionMessage != null)
                    Text(
                      _suggestionMessage!,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  if (_suggestions != null &&
                      !_suggestions!.isEmpty &&
                      (!_suggestedByAi || _hasEditedAiSuggestion))
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => _applySuggestions(replace: true),
                      child: Text(
                        _suggestedByAi
                            ? 'Reapply AI suggestions'
                            : 'Apply OCR suggestions',
                      ),
                    ),
                ],

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
                      _markManual(_OcrField.content);
                      _markManual(_OcrField.folder);
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
                  onChanged: (val) => setState(() {
                    _selectedFolder = val;
                    _markManual(_OcrField.folder);
                    // Keep the category that owns a manually selected folder.
                    _markManual(_OcrField.content);
                  }),
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
                  onDateSelected: (d) => setState(() {
                    _selectedDate = d;
                    _markManual(_OcrField.date);
                  }),
                ),
                const SizedBox(height: 14),

                // Description (optional)
                OptionalField(
                  label: 'Description',
                  hint: 'Enter description',
                  controller: _descriptionCtrl,
                  isEnabled: _descriptionEnabled,
                  onToggle: () => setState(() {
                    _descriptionEnabled = !_descriptionEnabled;
                    _markManual(_OcrField.description);
                  }),
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
