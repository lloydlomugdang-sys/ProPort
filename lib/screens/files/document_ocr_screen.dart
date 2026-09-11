import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../constants/app_colors.dart';
import '../../services/api_client.dart';
import '../../services/document_models.dart';
import '../../services/document_scope.dart';
import '../../widgets/grad_app_bar.dart';
import '../../widgets/primary_button.dart';

class DocumentOcrScreen extends StatefulWidget {
  const DocumentOcrScreen({super.key, required this.document});

  final DocumentRecord document;

  @override
  State<DocumentOcrScreen> createState() => _DocumentOcrScreenState();
}

class _DocumentOcrScreenState extends State<DocumentOcrScreen> {
  final _reviewedTextController = TextEditingController();
  bool _loadRequested = false;
  bool _isLoading = true;
  bool _isProcessing = false;
  bool _isSaving = false;
  String? _errorMessage;
  String? _successMessage;
  DocumentOcrResult? _ocr;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadRequested) return;
    _loadRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOcr());
  }

  @override
  void dispose() {
    _reviewedTextController.dispose();
    super.dispose();
  }

  Future<void> _loadOcr() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });
    try {
      final result = await DocumentScope.of(
        context,
      ).loadOcr(widget.document.id);
      if (mounted) _applyResult(result);
    } on ApiException catch (error) {
      if (mounted) setState(() => _errorMessage = _messageFor(error));
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage =
              'Unable to load extracted text. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _requestExtraction() async {
    if (_isProcessing || _isSaving) return;
    if (_ocr?.isReady == true) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Extract text again?'),
          content: const Text(
            'Running extraction again will replace the current reviewed text.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Extract Again'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _successMessage = null;
    });
    try {
      final result = await DocumentScope.of(
        context,
      ).extractText(widget.document.id);
      if (!mounted) return;
      _applyResult(result);
      _showSnack('Text extracted. Review it before saving changes.');
    } on ApiException catch (error) {
      await _refreshFailedStatus();
      if (mounted) setState(() => _errorMessage = _messageFor(error));
    } catch (_) {
      await _refreshFailedStatus();
      if (mounted) {
        setState(
          () => _errorMessage = 'Unable to extract text. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _refreshFailedStatus() async {
    try {
      final result = await DocumentScope.of(
        context,
      ).loadOcr(widget.document.id);
      if (mounted) _applyResult(result);
    } catch (_) {
      // Preserve the original safe extraction error.
    }
  }

  Future<void> _save() async {
    if (_isSaving || _isProcessing) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _successMessage = null;
    });
    try {
      final result = await DocumentScope.of(
        context,
      ).saveReviewedText(widget.document.id, _reviewedTextController.text);
      if (!mounted) return;
      _applyResult(result);
      setState(() => _successMessage = 'Text changes saved.');
      _showSnack('Text changes saved.');
    } on ApiException catch (error) {
      if (mounted) setState(() => _errorMessage = _messageFor(error));
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _errorMessage = 'Unable to save text changes. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _applyResult(DocumentOcrResult result) {
    _ocr = result;
    if (result.isReady) {
      _reviewedTextController.text =
          result.reviewedText ?? result.rawText ?? '';
    }
    setState(() {});
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  String _messageFor(ApiException error) {
    if (error.code == 'SCANNED_PDF_OCR_NOT_SUPPORTED') {
      return 'This PDF appears to be scanned. For this demo, upload the page as JPG or PNG to extract its text.';
    }
    return error.message;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const GradBackAppBar(title: 'Extracted Text'),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DocumentCard(document: widget.document),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      _MessageCard(message: _errorMessage!, isError: true),
                    ],
                    if (_successMessage != null) ...[
                      const SizedBox(height: 12),
                      _MessageCard(message: _successMessage!),
                    ],
                    const SizedBox(height: 16),
                    ..._statusContent(),
                  ],
                ),
              ),
      ),
    );
  }

  List<Widget> _statusContent() {
    final status = _ocr?.status ?? DocumentOcrStatus.notProcessed;
    if (status == DocumentOcrStatus.ready) {
      return [
        Text(
          'Review and edit the extracted text',
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('ocr-reviewed-text'),
          controller: _reviewedTextController,
          minLines: 12,
          maxLines: null,
          maxLength: 200000,
          decoration: InputDecoration(
            hintText: 'Extracted text will appear here.',
            filled: true,
            fillColor: AppColors.inputFill,
            alignLabelWithHint: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.inputBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.inputBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.inputBorderFocus,
                width: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: 'Save Changes',
          onPressed: _save,
          isLoading: _isSaving,
          icon: Icons.save_outlined,
        ),
        const SizedBox(height: 12),
        SecondaryButton(
          label: 'Extract Again',
          onPressed: _requestExtraction,
          icon: Icons.document_scanner_outlined,
        ),
      ];
    }

    if (status == DocumentOcrStatus.processing || _isProcessing) {
      return [
        const _MessageCard(
          message: 'Extracting text locally. This may take a moment.',
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: 'Extracting Text',
          onPressed: _requestExtraction,
          isLoading: true,
        ),
        if (!_isProcessing) ...[
          const SizedBox(height: 12),
          SecondaryButton(
            label: 'Refresh Status',
            onPressed: _loadOcr,
            icon: Icons.refresh,
          ),
        ],
      ];
    }

    final failed = status == DocumentOcrStatus.failed;
    return [
      _MessageCard(
        message: failed
            ? 'The last text extraction did not complete. Your original file is unchanged.'
            : 'Extract text from this ${widget.document.fileKind == 'pdf' ? 'PDF' : 'image'}, then review and save any corrections.',
        isError: failed,
      ),
      const SizedBox(height: 16),
      PrimaryButton(
        label: failed ? 'Try Again' : 'Extract Text',
        onPressed: _requestExtraction,
        isLoading: _isProcessing,
        icon: Icons.document_scanner_outlined,
      ),
    ];
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.document});

  final DocumentRecord document;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Icon(
            document.fileKind == 'pdf'
                ? Icons.picture_as_pdf_outlined
                : Icons.image_outlined,
            color: document.fileKind == 'pdf'
                ? AppColors.filePdf
                : AppColors.fileImage,
            size: 32,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  document.originalFileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError
            ? AppColors.danger.withValues(alpha: 0.08)
            : AppColors.surface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError
              ? AppColors.danger.withValues(alpha: 0.3)
              : AppColors.cardBorder,
        ),
      ),
      child: Text(
        message,
        style: GoogleFonts.poppins(
          fontSize: 13,
          color: isError ? AppColors.danger : AppColors.textSecondary,
        ),
      ),
    );
  }
}
