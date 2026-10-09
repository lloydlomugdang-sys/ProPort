// LOCATION: lib/screens/portfolio/portfolio_preview_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../services/document_models.dart';
import '../../services/document_scope.dart';
import '../../services/document_service.dart';
import '../../services/portfolio_export_service.dart';
import '../../services/portfolio_scope.dart';
import '../../widgets/grad_app_bar.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/document_image_preview.dart';
import '../../widgets/document_pdf_preview.dart';
import '../../widgets/document_unsupported_preview.dart';
import '../files/document_ocr_screen.dart';
import 'models/portfolio_models.dart';
import 'models/portfolio_document_order.dart';
import 'portfolio_list_screen.dart';
import 'portfolio_export_screen.dart';
import 'widgets/portfolio_documents_builder.dart';
import '../../widgets/app_empty_state.dart';

/// Read-only preview of saved portfolio information.
/// Styled to resemble the first page of an academic PDF document rather
/// than a Canva-style editor — this is a static, print-like preview.
///
/// Displays the saved title page and current authenticated document details.
class PortfolioPreviewScreen extends StatefulWidget {
  const PortfolioPreviewScreen({
    super.key,
    required this.portfolioInfo,
    this.exportFormat,
    this.initialExportedFile,
    this.exporter,
  });

  final PortfolioInfo portfolioInfo;

  /// Format of the file created immediately before opening this preview.
  final ExportFormat? exportFormat;

  /// Already-generated file artifact if navigated from export completion.
  final PortfolioExportFile? initialExportedFile;

  /// Injected exporter for tests; defaults to PortfolioScope.exporterOf.
  final PortfolioExporter? exporter;

  @override
  State<PortfolioPreviewScreen> createState() => _PortfolioPreviewScreenState();
}

class _PortfolioPreviewScreenState extends State<PortfolioPreviewScreen> {
  PortfolioExportFile? _exportedFile;
  bool _isSaving = false;
  bool _isSharing = false;
  bool _isGenerating = false;

  PortfolioExporter get _exporter =>
      widget.exporter ?? PortfolioScope.exporterOf(context);

  @override
  void initState() {
    super.initState();
    _exportedFile = widget.initialExportedFile;
  }

  void _showFeedback(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.danger : AppColors.primary,
        duration: Duration(seconds: isError ? 4 : 3),
      ),
    );
  }

  Future<PortfolioExportFile?> _ensureExportedFile(ExportFormat format) async {
    if (_exportedFile != null && _exportedFile!.format == format) {
      return _exportedFile;
    }
    if (!mounted) return null;
    final docService = DocumentScope.maybeOf(context);
    if (docService == null) {
      _showFeedback(
        "We couldn't save your portfolio. Please try again.",
        isError: true,
      );
      return null;
    }

    setState(() => _isGenerating = true);
    try {
      await docService.load(force: true);
      if (!mounted) return null;
      final content = PortfolioExportContent.fromDocuments(
        widget.portfolioInfo,
        docService,
      );
      final file = await _exporter.generate(content, format);
      if (!mounted) return null;
      setState(() {
        _exportedFile = file;
      });
      return file;
    } catch (error) {
      if (mounted) {
        _showFeedback(portfolioExportError(error), isError: true);
      }
      return null;
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<ExportFormat?> _showFormatPicker(BuildContext context) {
    return showModalBottomSheet<ExportFormat>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Save to Device',
                style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose your preferred format to download:',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                key: const Key('format-picker-pdf'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.cardBorder),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.filePdf.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf_rounded,
                    color: AppColors.filePdf,
                  ),
                ),
                title: Text(
                  'PDF Document',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Standard academic portfolio with embedded files',
                  style: AppTextStyles.labelSmall,
                ),
                onTap: () => Navigator.pop(sheetContext, ExportFormat.pdf),
              ),
              const SizedBox(height: 10),
              ListTile(
                key: const Key('format-picker-docx'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.cardBorder),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.description_rounded,
                    color: AppColors.primary,
                  ),
                ),
                title: Text(
                  'DOCX Document',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Editable outline for Microsoft Word',
                  style: AppTextStyles.labelSmall,
                ),
                onTap: () => Navigator.pop(sheetContext, ExportFormat.docx),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onSaveToDevice() async {
    if (_isSaving || _isSharing || _isGenerating) return;

    PortfolioExportFile? file = _exportedFile;
    if (file == null) {
      final chosenFormat =
          widget.exportFormat ?? await _showFormatPicker(context);
      if (chosenFormat == null) return;
      if (!mounted) return;
      file = await _ensureExportedFile(chosenFormat);
      if (file == null) return;
    }

    setState(() => _isSaving = true);
    try {
      final saved = await _exporter.saveToDevice(file);
      if (saved && mounted) {
        _showFeedback('Portfolio saved successfully.');
      }
    } catch (_) {
      if (mounted) {
        _showFeedback(
          "We couldn't save your portfolio. Please try again.",
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _onShare([BuildContext? buttonContext]) async {
    if (_isSharing || _isSaving || _isGenerating) return;

    final targetContext = buttonContext ?? context;
    final box = targetContext.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 100, 100);

    PortfolioExportFile? file = _exportedFile;
    if (file == null) {
      final chosenFormat =
          widget.exportFormat ?? await _showFormatPicker(context);
      if (chosenFormat == null) return;
      if (!mounted) return;
      file = await _ensureExportedFile(chosenFormat);
      if (file == null) return;
    }

    setState(() => _isSharing = true);
    try {
      await _exporter.share(file, origin);
    } catch (_) {
      if (mounted) {
        _showFeedback(
          'Unable to share the file. Please try again or export a new copy.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  // ─── Actions ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: GradBackAppBar(
        title: 'Portfolio Preview',
        onBack: () => Navigator.pop(context),
        actions: [
          Builder(
            builder: (btnCtx) => IconButton(
              key: const Key('portfolio-preview-share-btn'),
              tooltip: 'Share',
              icon: _isSharing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.share_rounded),
              onPressed: (_isSaving || _isSharing || _isGenerating)
                  ? null
                  : () => _onShare(btnCtx),
            ),
          ),
          IconButton(
            key: const Key('portfolio-preview-download-btn'),
            tooltip: 'Save to Device',
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
            onPressed: (_isSaving || _isSharing || _isGenerating)
                ? null
                : _onSaveToDevice,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: _PreviewSheet(
                      portfolioInfo: widget.portfolioInfo,
                      exportFormat:
                          _exportedFile?.format ?? widget.exportFormat,
                    ),
                  ),
                ),
              ),
            ),

            // ── Bottom actions ─────────────────────────────────────────
            if (widget.exportFormat == null && _exportedFile == null)
              TextButton.icon(
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Export Portfolio'),
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PortfolioExportScreen(
                      portfolioInfo: widget.portfolioInfo,
                    ),
                  ),
                ),
              ),
            _buildBottomActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const Key('portfolio-preview-save-btn'),
                onPressed: (_isSaving || _isSharing || _isGenerating)
                    ? null
                    : _onSaveToDevice,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download_rounded, size: 20),
                label: Text(
                  _isSaving
                      ? 'Saving...'
                      : (_isGenerating ? 'Generating...' : 'Save to Device'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Back',
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: PrimaryButton(
                    label: 'My Portfolios',
                    onPressed: () => PortfolioListScreen.returnToList(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Logical content preview; the server owns the printable Letter-page layout.
class _PreviewSheet extends StatelessWidget {
  const _PreviewSheet({required this.portfolioInfo, this.exportFormat});

  final PortfolioInfo portfolioInfo;
  final ExportFormat? exportFormat;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDocumentHeader(),
          const SizedBox(height: 24),
          _buildDivider(),
          const SizedBox(height: 20),
          _buildStudentInfoSection(),
          const SizedBox(height: 24),
          PortfolioDocumentsBuilder(
            builder: (documents) {
              final summary = PortfolioSummary.fromDocumentSummary(
                documents.summary,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (documents.documents.any(
                    (doc) =>
                        PortfolioDocumentOrder.sectionFor(doc) ==
                        'Creative Title',
                  )) ...[
                    _buildDocuments(
                      context,
                      documents,
                      summary,
                      creativeOnly: true,
                    ),
                    const SizedBox(height: 24),
                  ],
                  _buildSectionsIncluded(summary.sections),
                  const SizedBox(height: 24),
                  _buildDocuments(context, documents, summary),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          _buildFooterNote(),
        ],
      ),
    );
  }

  // ── Document header ───────────────────────────────────────────────────
  Widget _buildDocumentHeader() {
    return Column(
      children: [
        Text(
          'Standard Title',
          textAlign: TextAlign.center,
          style: AppTextStyles.h2.copyWith(
            color: AppColors.primary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'ACADEMIC PORTFOLIO',
          textAlign: TextAlign.center,
          style: AppTextStyles.h4.copyWith(
            color: AppColors.textPrimary,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(height: 1, color: AppColors.divider);
  }

  // ── Student information ───────────────────────────────────────────────
  Widget _buildStudentInfoSection() {
    final fields = <MapEntry<String, String>>[
      MapEntry('Full Name', portfolioInfo.fullName),
      MapEntry('Year & Section', portfolioInfo.yearAndSection),
      MapEntry('Schedule', portfolioInfo.formattedSchedule),
      MapEntry('Instructor', portfolioInfo.instructorName),
      MapEntry('Course', portfolioInfo.course),
      MapEntry('Course Code', portfolioInfo.courseCode),
      MapEntry('Semester & Academic Year', portfolioInfo.semesterAndYear),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Student Information',
          style: AppTextStyles.sectionHeader.copyWith(color: AppColors.primary),
        ),
        const SizedBox(height: 12),
        ...fields.map((f) => _InfoRow(label: f.key, value: f.value)),
      ],
    );
  }

  // ── Sections included table ───────────────────────────────────────────
  Widget _buildSectionsIncluded(List<PortfolioSection> sections) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sections Included',
          style: AppTextStyles.sectionHeader.copyWith(color: AppColors.primary),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder, width: 1.2),
          ),
          child: Column(
            children: List.generate(sections.length, (index) {
              final section = sections[index];
              final isLast = index == sections.length - 1;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: index.isEven
                      ? Colors.white
                      : AppColors.background.withValues(alpha: 0.25),
                  border: isLast
                      ? null
                      : const Border(
                          bottom: BorderSide(color: AppColors.divider),
                        ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        PortfolioDocumentOrder.label(section.name),
                        style: AppTextStyles.bodyMedium,
                      ),
                    ),
                    Text(
                      '${section.count}',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildDocuments(
    BuildContext context,
    DocumentService service,
    PortfolioSummary summary, {
    bool creativeOnly = false,
  }) {
    final documents =
        PortfolioDocumentOrder.sorted(service.documents, service.categories)
            .where(
              (doc) =>
                  (PortfolioDocumentOrder.sectionFor(doc) ==
                      'Creative Title') ==
                  creativeOnly,
            )
            .toList();
    final groups = <String>{
      ...summary.sections.map((section) => section.name),
      ...documents.map(PortfolioDocumentOrder.sectionFor),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!creativeOnly)
          Text(
            'Document Details',
            style: AppTextStyles.sectionHeader.copyWith(
              color: AppColors.primary,
            ),
          ),
        const SizedBox(height: 12),
        if (service.documents.isEmpty && !creativeOnly)
          const AppEmptyState(
            isCompact: true,
            title: 'No documents yet',
            description: 'No stored documents to include yet.',
            icon: Icons.description_outlined,
          ),
        if (!creativeOnly && service.documents.length < summary.totalItems)
          Text(
            'Showing ${service.documents.length} of ${summary.totalItems} documents returned by the current list. Section counts include all stored documents. The server PDF export retrieves all documents within its export limits.',
            style: AppTextStyles.bodySmall,
          ),
        for (final group in groups)
          if (documents.any(
            (document) => PortfolioDocumentOrder.sectionFor(document) == group,
          )) ...[
            Text(
              PortfolioDocumentOrder.label(group),
              style: AppTextStyles.h4.copyWith(color: AppColors.primary),
            ),
            const SizedBox(height: 8),
            for (final document in documents.where(
              (document) =>
                  PortfolioDocumentOrder.sectionFor(document) == group,
            ))
              _buildDocumentDetails(context, document, service.categories),
          ],
      ],
    );
  }

  Widget _buildDocumentDetails(
    BuildContext context,
    DocumentRecord document,
    List<DocumentCategory> categories,
  ) {
    final category = categories
        .where((value) => value.key == document.categoryKey)
        .firstOrNull;
    final folder = category?.folders
        .where((value) => value.key == document.folderKey)
        .firstOrNull;
    final ext = document.originalFileName.contains('.')
        ? document.originalFileName.split('.').last.toLowerCase()
        : document.extension.replaceAll('.', '').toLowerCase();
    final isPdf =
        document.fileKind == 'pdf' ||
        ext == 'pdf' ||
        document.originalFileName.toLowerCase().endsWith('.pdf');
    final isImage =
        !isPdf &&
        (document.fileKind == 'image' ||
            const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'].contains(ext) ||
            document.mimeType.startsWith('image/'));

    final Color typeColor = isPdf
        ? AppColors.filePdf
        : (isImage ? AppColors.fileImage : AppColors.primary);
    final IconData typeIcon = isPdf
        ? Icons.picture_as_pdf_rounded
        : (isImage ? Icons.image_rounded : Icons.description_rounded);

    void openDetails() {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => DocumentOcrScreen(document: document),
        ),
      );
    }

    return Container(
      key: ValueKey('preview-document-${document.id}'),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: openDetails,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(typeIcon, size: 20, color: typeColor),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            document.title,
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${category?.name ?? document.categoryKey} / ${folder?.name ?? document.folderKey}',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
                if (isImage) ...[
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.background.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: DocumentImagePreview(
                      documentId: document.id,
                      fit: BoxFit.contain,
                      maxHeight: 260,
                      borderRadius: BorderRadius.circular(8),
                      showFullScreenOnTap: true,
                      cacheWidth: 1080,
                    ),
                  ),
                  if (document.pageCount > 1) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${document.pageCount} pages • Page 1 shown',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ] else if (isPdf) ...[
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.background.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: DocumentPdfPreview(
                      documentId: document.id,
                      fileName: document.originalFileName,
                      pageCount: document.pageCount,
                      fit: BoxFit.contain,
                      maxHeight: 260,
                      borderRadius: BorderRadius.circular(8),
                      onTap: openDetails,
                    ),
                  ),
                  if (document.pageCount > 1) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.filePdf.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${document.pageCount} pages • Page 1 shown',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.filePdf,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ] else ...[
                  const SizedBox(height: 12),
                  DocumentUnsupportedPreview(
                    document: document,
                    onTap: openDetails,
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 13,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      document.documentDate.toIso8601String().substring(0, 10),
                      style: AppTextStyles.labelMedium,
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.attach_file_rounded,
                      size: 13,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        document.originalFileName,
                        style: AppTextStyles.labelSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (document.description?.trim().isNotEmpty ?? false) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    decoration: BoxDecoration(
                      color: AppColors.background.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                      border: const Border(
                        left: BorderSide(color: AppColors.primary, width: 3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Description',
                          style: AppTextStyles.labelSmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          document.description!,
                          style: AppTextStyles.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
                if (document.reflection?.trim().isNotEmpty ?? false) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: const Border(
                        left: BorderSide(color: AppColors.secondary, width: 3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reflection',
                          style: AppTextStyles.labelSmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.secondary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          document.reflection!,
                          style: AppTextStyles.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Footer note ───────────────────────────────────────────────────────
  Widget _buildFooterNote() {
    return Column(
      children: [
        _buildDivider(),
        const SizedBox(height: 14),
        Text(
          'Title page saved in My Portfolios. This preview uses your current document details and visual previews of stored files.',
          textAlign: TextAlign.center,
          style: AppTextStyles.labelSmall.copyWith(fontStyle: FontStyle.italic),
        ),
        if (exportFormat != null)
          Text(
            'Generated format: ${exportFormat!.label}',
            style: AppTextStyles.labelSmall,
          ),
      ],
    );
  }
}

// ─── Student info row ─────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final displayValue = value.trim().isEmpty ? '\u2014' : value;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 148,
            child: Text(label, style: AppTextStyles.labelMedium),
          ),
          Expanded(
            child: Text(
              displayValue,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
