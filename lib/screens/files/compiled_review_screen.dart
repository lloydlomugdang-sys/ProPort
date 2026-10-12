// LOCATION: lib/screens/files/compiled_review_screen.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../constants/app_colors.dart';
import '../../services/api_client.dart';
import '../../services/document_models.dart';
import '../../services/document_scope.dart';
import '../../widgets/grad_app_bar.dart';
import '../../widgets/primary_button.dart';
import 'widgets/custom_dropdown.dart';
import 'widgets/date_picker_field.dart';

class _EditableSegment {
  _EditableSegment({
    required this.startPage,
    required this.endPage,
    required this.categoryKey,
    required this.folderKey,
    required String title,
    this.documentDate,
    String? description,
    String? reflection,
    this.confidence = 0.8,
    this.rationale,
    this.warning,
  }) : titleCtrl = TextEditingController(text: title),
       descCtrl = TextEditingController(text: description ?? ''),
       reflCtrl = TextEditingController(text: reflection ?? '');

  int startPage;
  int endPage;
  String? categoryKey;
  String? folderKey;
  DateTime? documentDate;
  final double confidence;
  final String? rationale;
  final String? warning;
  final TextEditingController titleCtrl;
  final TextEditingController descCtrl;
  final TextEditingController reflCtrl;
  bool showDetails = false;
  bool confirmedUnresolved = false;

  void dispose() {
    titleCtrl.dispose();
    descCtrl.dispose();
    reflCtrl.dispose();
  }
}

class CompiledReviewScreen extends StatefulWidget {
  const CompiledReviewScreen({
    super.key,
    required this.analysis,
    required this.file,
  });

  final CompiledAnalysisResult analysis;
  final PickedDocument file;

  @override
  State<CompiledReviewScreen> createState() => _CompiledReviewScreenState();
}

class _CompiledReviewScreenState extends State<CompiledReviewScreen> {
  final List<_EditableSegment> _segments = [];
  bool _isSubmitting = false;
  bool _allowPop = false;
  bool _cancelOpen = false;
  late CompiledAnalysisResult _analysis;
  String _idempotencyKey =
      'split_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';
  List<CompiledSplitSegment>? _submittedSegments;

  @override
  void initState() {
    super.initState();
    _analysis = widget.analysis;
    for (final doc in widget.analysis.documents) {
      _segments.add(
        _EditableSegment(
          startPage: doc.startPage,
          endPage: doc.endPage,
          categoryKey: doc.categoryKey,
          folderKey: doc.folderKey,
          title: doc.title,
          documentDate: doc.documentDate,
          confidence: doc.confidence,
          rationale: doc.rationale,
          warning: doc.warning,
        ),
      );
    }
    // If no proposals were returned, create at least 1 segment spanning the entire document
    if (_segments.isEmpty) {
      _segments.add(
        _EditableSegment(
          startPage: 1,
          endPage: widget.analysis.totalPages,
          categoryKey: null,
          folderKey: null,
          title: widget.analysis.originalFileName.replaceAll(
            RegExp(r'\.pdf$', caseSensitive: false),
            '',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    for (final seg in _segments) {
      seg.dispose();
    }
    super.dispose();
  }

  DocumentCategory? _findCategory(
    List<DocumentCategory> categories,
    String? key,
  ) {
    if (key == null) return null;
    for (final c in categories) {
      if (c.key == key) return c;
    }
    return null;
  }

  DocumentFolder? _findFolder(DocumentCategory? cat, String? key) {
    if (cat == null || key == null) return null;
    for (final f in cat.folders) {
      if (f.key == key) return f;
    }
    return null;
  }

  void _addSegment() {
    if (_submittedSegments != null || _isSubmitting) return;
    final lastEnd = _segments.isNotEmpty ? _segments.last.endPage : 0;
    final nextStart = min(lastEnd + 1, widget.analysis.totalPages);
    final nextEnd = widget.analysis.totalPages;

    setState(() {
      _segments.add(
        _EditableSegment(
          startPage: nextStart,
          endPage: nextEnd,
          categoryKey: null,
          folderKey: null,
          title: 'Document ${_segments.length + 1}',
        ),
      );
    });
  }

  void _removeSegment(int index) {
    if (_submittedSegments != null || _isSubmitting) return;
    if (_segments.length <= 1) return;
    setState(() {
      final removed = _segments.removeAt(index);
      removed.dispose();
    });
  }

  Future<void> _handleCancel() async {
    if (_isSubmitting || _cancelOpen) return;
    _cancelOpen = true;
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(
          'Discard Separation?',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Text(
          _submittedSegments == null
              ? 'Leaving now will cancel document separation. The compiled file will not be saved.'
              : 'The request may already have saved documents. Leaving does not undo a completed split. Check your Files before starting another upload.',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Stay'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (shouldLeave == true && mounted) {
      final service = DocumentScope.of(context);
      final cancelled = await service.cancelCompiledSession(
        _analysis.sessionId,
      );
      if (!mounted) return;
      if (cancelled) {
        setState(() => _allowPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context, false);
        });
      } else {
        _showSnack('Temporary cleanup could not finish. Please retry Cancel.');
      }
    }
    _cancelOpen = false;
  }

  Future<void> _retryAnalysis() async {
    if (_isSubmitting || _submittedSegments != null) return;
    final service = DocumentScope.of(context);
    setState(() => _isSubmitting = true);
    try {
      final updated = await service.analyzeCompiledDocument(widget.file);
      if (!mounted) {
        await service.cancelCompiledSession(updated.sessionId);
        return;
      }
      final previous = _analysis.sessionId;
      // Update extraction status/session only. Never overwrite reviewed fields or ranges.
      setState(() {
        _analysis = updated;
        _idempotencyKey =
            'split_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';
      });
      await service.cancelCompiledSession(previous);
    } catch (_) {
      if (mounted) {
        _showSnack(
          'Analysis could not finish. Your edits were kept. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  bool _segmentHasUnresolvedPages(_EditableSegment seg) {
    return _analysis.pages.any(
      (page) =>
          page.pageNumber >= seg.startPage &&
          page.pageNumber <= seg.endPage &&
          page.isUnresolved,
    );
  }

  bool _segmentHasUsableText(_EditableSegment seg) {
    final text = _analysis.pages
        .where(
          (page) =>
              page.pageNumber >= seg.startPage &&
              page.pageNumber <= seg.endPage &&
              !page.isUnresolved,
        )
        .map((page) => page.text.trim())
        .where((value) => value.isNotEmpty)
        .join('\n');
    return text.length >= 25;
  }

  Future<void> _handleSplitAndSave() async {
    if (_isSubmitting) return;
    if (_analysis.hasUnresolvedPages) {
      final hasUnconfirmedUnresolved = _segments.any(
        (seg) =>
            _segmentHasUnresolvedPages(seg) &&
            (!seg.confirmedUnresolved ||
                (!_segmentHasUsableText(seg) &&
                    seg.descCtrl.text.trim().isEmpty)),
      );
      if (hasUnconfirmedUnresolved) {
        _showSnack(
          'Unreadable pages must be retried or explicitly confirmed before separation.',
        );
        return;
      }
    }
    final totalPages = widget.analysis.totalPages;
    final categories = DocumentScope.of(context).categories;

    // Validate segments
    var nextPage = 1;
    for (var i = 0; i < _segments.length; i++) {
      final seg = _segments[i];
      if (seg.startPage != nextPage) {
        _showSnack(
          'Every page must appear exactly once, in order, without gaps or overlaps.',
        );
        return;
      }
      nextPage = seg.endPage + 1;
      if (seg.documentDate == null) {
        _showSnack('Document ${i + 1}: Please confirm the document date.');
        return;
      }
      if (seg.startPage < 1 || seg.startPage > totalPages) {
        _showSnack(
          'Document ${i + 1}: Start page must be between 1 and $totalPages.',
        );
        return;
      }
      if (seg.endPage < seg.startPage || seg.endPage > totalPages) {
        _showSnack(
          'Document ${i + 1}: End page must be between ${seg.startPage} and $totalPages.',
        );
        return;
      }
      if (seg.titleCtrl.text.trim().isEmpty) {
        _showSnack('Document ${i + 1}: Please enter a title.');
        return;
      }
      final cat = _findCategory(categories, seg.categoryKey);
      if (cat == null) {
        _showSnack(
          'Document ${i + 1}: Please select a valid document category.',
        );
        return;
      }
      final folder = _findFolder(cat, seg.folderKey);
      if (folder == null) {
        _showSnack('Document ${i + 1}: Please select a valid folder.');
        return;
      }
    }
    if (nextPage != totalPages + 1) {
      _showSnack('Include every page through page $totalPages before saving.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final service = DocumentScope.of(context);
      final splitSegments = _submittedSegments ??= _segments.map((seg) {
        return CompiledSplitSegment(
          startPage: seg.startPage,
          endPage: seg.endPage,
          categoryKey: seg.categoryKey!,
          folderKey: seg.folderKey!,
          title: seg.titleCtrl.text.trim(),
          documentDate: seg.documentDate ?? DateTime.now(),
          description: seg.descCtrl.text.trim().isNotEmpty
              ? seg.descCtrl.text.trim()
              : null,
          reflection: seg.reflCtrl.text.trim().isNotEmpty
              ? seg.reflCtrl.text.trim()
              : null,
        );
      }).toList();

      final createdDocs = await service.splitCompiledDocument(
        sessionId: _analysis.sessionId,
        idempotencyKey: _idempotencyKey,
        segments: splitSegments,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Successfully separated and saved ${createdDocs.length} documents.',
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );

      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      if (e.statusCode == 400 || e.statusCode == 422) _submittedSegments = null;
      _showSnack(
        e.message.isNotEmpty
            ? e.message
            : 'Separation failed. Please try again.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showSnack('Unable to complete document separation. Please try again.');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = DocumentScope.of(context);
    final categories = service.categories;

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleCancel();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: GradBackAppBar(
          title: 'Separate Portfolio (${_segments.length} Docs)',
        ),
        body: Stack(
          children: [
            Column(
              children: [
                _buildHeaderCard(),
                if (_analysis.pages.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${_analysis.pages.where((page) => page.source == 'digital').length} digital · '
                          '${_analysis.pages.where((page) => page.source == 'ocr').length} OCR · '
                          '${_analysis.pages.where((page) => page.source == 'blank').length} blank'
                          '${_analysis.hasUnresolvedPages ? '\nUnreadable pages: ${_analysis.pages.where((page) => page.isUnresolved).map((page) => page.pageNumber).join(', ')} — retry required' : ''}',
                          style: GoogleFonts.poppins(fontSize: 11),
                        ),
                        if (_analysis.hasUnresolvedPages)
                          TextButton(
                            onPressed: _isSubmitting ? null : _retryAnalysis,
                            child: const Text('Retry PDF analysis'),
                          ),
                        if (_submittedSegments != null && !_isSubmitting)
                          const Text(
                            'Retry uses the same reviewed values to prevent duplicate documents.',
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: _segments.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _segments.length) {
                        return _buildAddSegmentButton();
                      }
                      return AbsorbPointer(
                        absorbing: _submittedSegments != null,
                        child: _buildSegmentCard(index, categories),
                      );
                    },
                  ),
                ),
                _buildBottomBar(),
              ],
            ),
            if (_isSubmitting) _buildLoadingOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.divider, width: 1.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.filePdf.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.picture_as_pdf_rounded,
              color: AppColors.filePdf,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.analysis.originalFileName,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${widget.analysis.totalPages} Pages',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Proposed ${_segments.length} document sections. Review categories, dates, and complete page coverage before saving.',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentCard(int index, List<DocumentCategory> categories) {
    final seg = _segments[index];
    final currentCat = _findCategory(categories, seg.categoryKey);
    final currentFolder = _findFolder(currentCat, seg.folderKey);
    final totalPages = widget.analysis.totalPages;
    final pageCount = seg.endPage - seg.startPage + 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Header
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Document ${index + 1}',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.statusCompleteBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$pageCount page${pageCount > 1 ? 's' : ''}',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.statusCompleteText,
                    ),
                  ),
                ),
                if (_segments.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    color: AppColors.danger,
                    tooltip: 'Remove document section',
                    onPressed: () => _removeSegment(index),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (seg.warning != null && seg.warning!.trim().isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFB300)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: Color(0xFFE65100),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            seg.warning!,
                            style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFFE65100),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (seg.rationale != null &&
                    seg.rationale!.trim().isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      seg.rationale!,
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
                if (_segmentHasUnresolvedPages(seg)) ...[
                  CheckboxListTile(
                    value: seg.confirmedUnresolved,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      'Confirm reviewed details for unreadable page(s)',
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    onChanged: (val) {
                      setState(() => seg.confirmedUnresolved = val ?? false);
                    },
                  ),
                  const SizedBox(height: 6),
                ],
                // Page range selectors
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Start Page',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.inputBorder),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                value: seg.startPage,
                                isExpanded: true,
                                items: List.generate(
                                  totalPages,
                                  (p) => DropdownMenuItem(
                                    value: p + 1,
                                    child: Text(
                                      'Page ${p + 1}',
                                      style: GoogleFonts.poppins(fontSize: 13),
                                    ),
                                  ),
                                ),
                                onChanged: (newVal) {
                                  if (newVal == null) return;
                                  setState(() {
                                    seg.startPage = newVal;
                                    if (seg.endPage < seg.startPage) {
                                      seg.endPage = seg.startPage;
                                    }
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'End Page',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.inputBorder),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                value: seg.endPage,
                                isExpanded: true,
                                items: List.generate(
                                  totalPages,
                                  (p) => DropdownMenuItem(
                                    value: p + 1,
                                    child: Text(
                                      'Page ${p + 1}',
                                      style: GoogleFonts.poppins(fontSize: 13),
                                    ),
                                  ),
                                ),
                                onChanged: (newVal) {
                                  if (newVal == null) return;
                                  setState(() {
                                    seg.endPage = newVal;
                                    if (seg.startPage > seg.endPage) {
                                      seg.startPage = seg.endPage;
                                    }
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Category Dropdown
                CustomDropdown(
                  label: 'Content',
                  hint: 'Select Category',
                  required: true,
                  items: categories.map((c) => c.name).toList(),
                  value: currentCat?.name,
                  onChanged: (selectedName) {
                    final selected = categories
                        .where((c) => c.name == selectedName)
                        .firstOrNull;
                    setState(() {
                      seg.categoryKey = selected?.key;
                      seg.folderKey = selected?.folders.firstOrNull?.key;
                    });
                  },
                ),
                const SizedBox(height: 10),

                // Folder Dropdown
                CustomDropdown(
                  label: 'Folder',
                  hint: 'Select Folder',
                  required: true,
                  enabled: currentCat != null,
                  items:
                      currentCat?.folders.map((f) => f.name).toList() ??
                      const [],
                  value: currentFolder?.name,
                  onChanged: (selectedName) {
                    final selected = currentCat?.folders
                        .where((f) => f.name == selectedName)
                        .firstOrNull;
                    setState(() {
                      seg.folderKey = selected?.key;
                    });
                  },
                ),
                const SizedBox(height: 10),

                // Document Title
                Text(
                  'Document Title *',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: seg.titleCtrl,
                  maxLength: 250,
                  decoration: InputDecoration(
                    hintText: 'e.g. Curriculum Vitae',
                    counterText: '',
                    hintStyle: GoogleFonts.poppins(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.cardBorder),
                    ),
                  ),
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),

                // Document Date
                DatePickerField(
                  label: 'Document Date',
                  required: true,
                  selectedDate: seg.documentDate,
                  onDateSelected: (date) {
                    setState(() => seg.documentDate = date);
                  },
                ),

                // Toggle Additional Details
                const SizedBox(height: 8),
                InkWell(
                  onTap: () {
                    setState(() => seg.showDetails = !seg.showDetails);
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          seg.showDetails
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          seg.showDetails
                              ? 'Hide optional description & reflection'
                              : 'Add description & reflection (optional)',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (seg.showDetails) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Description',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: seg.descCtrl,
                    maxLines: 2,
                    maxLength: 2000,
                    decoration: InputDecoration(
                      hintText: 'Brief description',
                      counterText: '',
                      contentPadding: const EdgeInsets.all(10),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.cardBorder,
                        ),
                      ),
                    ),
                    style: GoogleFonts.poppins(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Reflection',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: seg.reflCtrl,
                    maxLines: 2,
                    maxLength: 5000,
                    decoration: InputDecoration(
                      hintText: 'Personal learning reflection',
                      counterText: '',
                      contentPadding: const EdgeInsets.all(10),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.cardBorder,
                        ),
                      ),
                    ),
                    style: GoogleFonts.poppins(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddSegmentButton() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: OutlinedButton.icon(
        onPressed: _addSegment,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text('Add Another Document Section'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.2),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: OutlinedButton(
              onPressed: _isSubmitting ? null : _handleCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.cardBorder),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: PrimaryButton(
              label: 'Separate & Save (${_segments.length})',
              icon: Icons.splitscreen_rounded,
              isLoading: _isSubmitting,
              onPressed: () {
                if (!_isSubmitting) {
                  _handleSplitAndSave();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Separating Documents...',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Slicing PDF & uploading individual files',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
