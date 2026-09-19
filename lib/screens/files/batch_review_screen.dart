import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../constants/app_colors.dart';
import '../../services/batch_upload_queue.dart';
import '../../services/document_models.dart';
import '../../services/document_scope.dart';
import '../../widgets/grad_app_bar.dart';
import 'models/batch_upload_item.dart';
import 'widgets/custom_dropdown.dart';
import 'widgets/date_picker_field.dart';

class BatchReviewScreen extends StatefulWidget {
  const BatchReviewScreen({super.key, required this.queue});

  final BatchUploadQueue queue;

  @override
  State<BatchReviewScreen> createState() => _BatchReviewScreenState();
}

class _BatchReviewScreenState extends State<BatchReviewScreen> {
  @override
  void initState() {
    super.initState();
    widget.queue.addListener(_onQueueChanged);
  }

  @override
  void dispose() {
    widget.queue.removeListener(_onQueueChanged);
    super.dispose();
  }

  void _onQueueChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final service = DocumentScope.of(context);
    final categories = service.categories;
    final queue = widget.queue;
    final items = queue.items;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: GradBackAppBar(
        title: 'Review Files (${queue.savedCount}/${queue.totalCount})',
      ),
      body: Column(
        children: [
          // Queue progress header
          _buildProgressBanner(queue),

          // Document review list
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      'No documents selected.',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: AppColors.textMuted,
                      ),
                    ),
                  )
                : ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _BatchItemCard(
                        key: ValueKey(item.id),
                        item: item,
                        index: index,
                        total: items.length,
                        categories: categories,
                        onUpdateMetadata: (metadata) {
                          queue.updateItemMetadata(
                            item.id,
                            categoryKey: metadata.categoryKey,
                            folderKey: metadata.folderKey,
                            title: metadata.title,
                            documentDate: metadata.documentDate,
                            description: metadata.description,
                            reflection: metadata.reflection,
                          );
                        },
                        onSave: () async {
                          final success = await queue.saveItem(item.id);
                          if (!context.mounted) return;
                          if (success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Saved "${item.title ?? item.fileName}"',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: Colors.white,
                                  ),
                                ),
                                backgroundColor: AppColors.success,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        onRetry: () => queue.retry(item.id),
                        onRemove: () => queue.remove(item.id),
                      );
                    },
                  ),
          ),
          if (items.isNotEmpty) _buildBottomBar(context, queue),
        ],
      ),
    );
  }

  Widget _buildProgressBanner(BatchUploadQueue queue) {
    final progress = queue.totalCount > 0
        ? (queue.savedCount + queue.readyCount) / queue.totalCount
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.divider, width: 1.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Processing: ${queue.totalCount} Documents',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '${queue.savedCount} saved • ${queue.readyCount} ready • ${queue.failedCount} failed',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: queue.isAllProcessed
                  ? 1.0
                  : (progress > 0 ? progress : null),
              backgroundColor: AppColors.divider,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
              minHeight: 7,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, BatchUploadQueue queue) {
    final canSave = queue.validToSaveCount > 0 && !queue.isSavingAll;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${queue.validToSaveCount} of ${queue.totalCount} Valid Documents',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    queue.isAllSaved
                        ? 'All documents saved!'
                        : 'Review details before saving',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: queue.isAllSaved
                          ? AppColors.success
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (queue.isAllSaved)
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: const Text('Finish Review'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: canSave ? () => _saveAll(context, queue) : null,
                icon: queue.isSavingAll
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.done_all_rounded, size: 18),
                label: Text(queue.isSavingAll ? 'Saving...' : 'Save All Valid'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.cardBorder,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAll(BuildContext context, BatchUploadQueue queue) async {
    final saved = await queue.saveAllValid();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Successfully saved $saved documents.',
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _ItemMetadataChange {
  const _ItemMetadataChange({
    this.categoryKey,
    this.folderKey,
    this.title,
    this.documentDate,
    this.description,
    this.reflection,
  });

  final String? categoryKey;
  final String? folderKey;
  final String? title;
  final DateTime? documentDate;
  final String? description;
  final String? reflection;
}

class _BatchItemCard extends StatefulWidget {
  const _BatchItemCard({
    super.key,
    required this.item,
    required this.index,
    required this.total,
    required this.categories,
    required this.onUpdateMetadata,
    required this.onSave,
    required this.onRetry,
    required this.onRemove,
  });

  final BatchUploadItem item;
  final int index;
  final int total;
  final List<DocumentCategory> categories;
  final ValueChanged<_ItemMetadataChange> onUpdateMetadata;
  final VoidCallback onSave;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  State<_BatchItemCard> createState() => _BatchItemCardState();
}

class _BatchItemCardState extends State<_BatchItemCard> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _reflCtrl;
  bool _showDetails = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.item.title ?? '');
    _descCtrl = TextEditingController(text: widget.item.description ?? '');
    _reflCtrl = TextEditingController(text: widget.item.reflection ?? '');
  }

  @override
  void didUpdateWidget(covariant _BatchItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.title != widget.item.title &&
        widget.item.title != null &&
        _titleCtrl.text != widget.item.title) {
      _titleCtrl.text = widget.item.title!;
    }
    if (oldWidget.item.description != widget.item.description &&
        widget.item.description != null &&
        _descCtrl.text != widget.item.description) {
      _descCtrl.text = widget.item.description!;
    }
    if (oldWidget.item.reflection != widget.item.reflection &&
        widget.item.reflection != null &&
        _reflCtrl.text != widget.item.reflection) {
      _reflCtrl.text = widget.item.reflection!;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _reflCtrl.dispose();
    super.dispose();
  }

  DocumentCategory? _findCategory(String? key) {
    if (key == null) return null;
    for (final cat in widget.categories) {
      if (cat.key == key) return cat;
    }
    return null;
  }

  DocumentFolder? _findFolder(DocumentCategory? cat, String? key) {
    if (cat == null || key == null) return null;
    for (final folder in cat.folders) {
      if (folder.key == key) return folder;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final currentCat = _findCategory(item.categoryKey);
    final currentFolder = _findFolder(currentCat, item.folderKey);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.isSaved
              ? AppColors.success.withValues(alpha: 0.6)
              : item.isFailed
              ? AppColors.danger.withValues(alpha: 0.6)
              : AppColors.cardBorder,
          width: item.isSaved || item.isFailed ? 1.5 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Item count, file name, status, remove button
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 8),
            child: Row(
              children: [
                _buildTypeIcon(item.fileName),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Document ${widget.index + 1} of ${widget.total}',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        item.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusChip(item),
                if (!item.isSaved && !item.isProcessing)
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                    tooltip: 'Remove',
                    onPressed: widget.onRemove,
                  ),
              ],
            ),
          ),

          // Processing states
          if (item.isProcessing) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.status == BatchItemStatus.extractingText
                          ? 'Extracting text and analyzing...'
                          : item.status == BatchItemStatus.aiCategorizing
                          ? 'AI categorizing document...'
                          : item.status == BatchItemStatus.uploading
                          ? 'Uploading to GradPort...'
                          : 'Waiting in queue...',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Failed state
          if (item.isFailed) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.errorMessage ?? 'Processing failed.',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.danger,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: widget.onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Retry'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Ready for review / Saved editable form
          if (item.isReadyForReview || item.isSaved) ...[
            // Confidence Badge & Warning
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: _buildConfidenceBadge(item),
            ),

            if (item.isLowConfidence)
              Container(
                margin: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: Colors.amber.shade800,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Low confidence: Please confirm the suggested category and folder.',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Form inputs
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Content (Category) Dropdown
                  CustomDropdown(
                    label: 'Content',
                    hint: 'Select Category',
                    required: true,
                    enabled: !item.isSaved,
                    items: widget.categories.map((c) => c.name).toList(),
                    value: currentCat?.name,
                    onChanged: (selectedName) {
                      final selected = widget.categories
                          .where((c) => c.name == selectedName)
                          .firstOrNull;
                      widget.onUpdateMetadata(
                        _ItemMetadataChange(
                          categoryKey: selected?.key,
                          folderKey: selected?.folders.firstOrNull?.key,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),

                  // Folder Dropdown
                  CustomDropdown(
                    label: 'Folder',
                    hint: 'Select Folder',
                    required: true,
                    enabled: !item.isSaved && currentCat != null,
                    items:
                        currentCat?.folders.map((f) => f.name).toList() ??
                        const [],
                    value: currentFolder?.name,
                    onChanged: (selectedName) {
                      final selected = currentCat?.folders
                          .where((f) => f.name == selectedName)
                          .firstOrNull;
                      widget.onUpdateMetadata(
                        _ItemMetadataChange(folderKey: selected?.key),
                      );
                    },
                  ),
                  const SizedBox(height: 10),

                  // Title Field
                  Row(
                    children: [
                      Text(
                        'Title',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
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
                  TextField(
                    controller: _titleCtrl,
                    enabled: !item.isSaved,
                    maxLength: 200,
                    decoration: InputDecoration(
                      hintText: 'Document title',
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
                        borderSide: const BorderSide(
                          color: AppColors.cardBorder,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.cardBorder,
                        ),
                      ),
                    ),
                    style: GoogleFonts.poppins(fontSize: 13),
                    onChanged: (val) {
                      widget.onUpdateMetadata(_ItemMetadataChange(title: val));
                    },
                  ),
                  const SizedBox(height: 10),

                  // Document Date
                  DatePickerField(
                    label: 'Date',
                    required: true,
                    selectedDate: item.documentDate,
                    onDateSelected: (date) {
                      widget.onUpdateMetadata(
                        _ItemMetadataChange(documentDate: date),
                      );
                    },
                  ),

                  // Optional details expander (Description & Reflection)
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () => setState(() => _showDetails = !_showDetails),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            _showDetails
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _showDetails
                                ? 'Hide Details'
                                : 'Add Description & Reflection',
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

                  if (_showDetails) ...[
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
                      controller: _descCtrl,
                      enabled: !item.isSaved,
                      maxLines: 2,
                      maxLength: 2000,
                      decoration: InputDecoration(
                        hintText: 'Brief description',
                        counterText: '',
                        hintStyle: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                        contentPadding: const EdgeInsets.all(10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: AppColors.cardBorder,
                          ),
                        ),
                      ),
                      style: GoogleFonts.poppins(fontSize: 12),
                      onChanged: (val) {
                        widget.onUpdateMetadata(
                          _ItemMetadataChange(description: val),
                        );
                      },
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
                      controller: _reflCtrl,
                      enabled: !item.isSaved,
                      maxLines: 2,
                      maxLength: 5000,
                      decoration: InputDecoration(
                        hintText: 'Personal learning reflection',
                        counterText: '',
                        hintStyle: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                        contentPadding: const EdgeInsets.all(10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: AppColors.cardBorder,
                          ),
                        ),
                      ),
                      style: GoogleFonts.poppins(fontSize: 12),
                      onChanged: (val) {
                        widget.onUpdateMetadata(
                          _ItemMetadataChange(reflection: val),
                        );
                      },
                    ),
                  ],

                  // Action Button for single document
                  if (!item.isSaved) ...[
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: item.isValidForSave ? widget.onSave : null,
                        icon: const Icon(Icons.check_rounded, size: 16),
                        label: const Text('Save Document'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.cardBorder,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Document saved to GradPort',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypeIcon(String name) {
    final lower = name.toLowerCase();
    final isPdf = lower.endsWith('.pdf');
    final isImage =
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png');

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color:
            (isPdf
                    ? AppColors.filePdf
                    : (isImage ? AppColors.fileImage : AppColors.primary))
                .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        isPdf
            ? Icons.picture_as_pdf_rounded
            : (isImage ? Icons.image_rounded : Icons.insert_drive_file_rounded),
        color: isPdf
            ? AppColors.filePdf
            : (isImage ? AppColors.fileImage : AppColors.primary),
        size: 20,
      ),
    );
  }

  Widget _buildStatusChip(BatchUploadItem item) {
    Color bg;
    Color fg;
    String label;

    switch (item.status) {
      case BatchItemStatus.waiting:
        bg = AppColors.cardBorder;
        fg = AppColors.textMuted;
        label = 'Waiting';
        break;
      case BatchItemStatus.extractingText:
        bg = AppColors.primary.withValues(alpha: 0.12);
        fg = AppColors.primary;
        label = 'OCR...';
        break;
      case BatchItemStatus.aiCategorizing:
        bg = Colors.purple.shade50;
        fg = Colors.purple.shade700;
        label = 'AI...';
        break;
      case BatchItemStatus.readyForReview:
        bg = AppColors.primary.withValues(alpha: 0.12);
        fg = AppColors.primary;
        label = 'Ready';
        break;
      case BatchItemStatus.uploading:
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade700;
        label = 'Saving...';
        break;
      case BatchItemStatus.saved:
        bg = AppColors.success.withValues(alpha: 0.15);
        fg = AppColors.success;
        label = 'Saved';
        break;
      case BatchItemStatus.failed:
        bg = AppColors.danger.withValues(alpha: 0.15);
        fg = AppColors.danger;
        label = 'Failed';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildConfidenceBadge(BatchUploadItem item) {
    final conf = item.confidence ?? 'low';
    final Color color;
    final String label;

    switch (conf) {
      case 'high':
        color = AppColors.success;
        label = 'High Confidence';
        break;
      case 'medium':
        color = Colors.amber.shade800;
        label = 'Medium Confidence';
        break;
      case 'low':
      default:
        color = AppColors.danger;
        label = 'Low Confidence';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
