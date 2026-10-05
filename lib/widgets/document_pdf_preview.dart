import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_colors.dart';
import '../services/document_scope.dart';

/// Renders a rasterized Page 1 thumbnail for a PDF document.
///
/// Features:
/// - Asynchronous rasterization of page 1 only (keeps memory bounded).
/// - Instant lookup from dedicated thumbnail cache.
/// - Polished loading indicator and fallback card on raster failure.
/// - "Page 1 • PDF" visual badge.
/// - Interactive tap affordance to open the full document details.
class DocumentPdfPreview extends StatefulWidget {
  const DocumentPdfPreview({
    super.key,
    required this.documentId,
    this.attachmentId,
    this.fit = BoxFit.contain,
    this.maxHeight = 260.0,
    this.maxWidth,
    this.width,
    this.height,
    this.borderRadius,
    this.pageCount = 1,
    this.fileName,
    this.onTap,
  });

  final String documentId;
  final String? attachmentId;
  final BoxFit fit;
  final double? maxHeight;
  final double? maxWidth;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final int pageCount;
  final String? fileName;
  final VoidCallback? onTap;

  @override
  State<DocumentPdfPreview> createState() => _DocumentPdfPreviewState();
}

class _DocumentPdfPreviewState extends State<DocumentPdfPreview> {
  Uint8List? _thumbnailBytes;
  bool _isLoading = false;
  bool _hasError = false;
  bool _loadInitiated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadInitiated) {
      _loadInitiated = true;
      _loadThumbnail();
    }
  }

  @override
  void didUpdateWidget(DocumentPdfPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documentId != widget.documentId ||
        oldWidget.attachmentId != widget.attachmentId) {
      _thumbnailBytes = null;
      _isLoading = false;
      _hasError = false;
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    final service = DocumentScope.of(context);

    // 1. Check synchronous thumbnail cache first
    final cached = service.getCachedThumbnail(
      widget.documentId,
      attachmentId: widget.attachmentId,
    );
    if (cached != null) {
      if (mounted) {
        setState(() {
          _thumbnailBytes = cached;
          _isLoading = false;
          _hasError = false;
        });
      }
      return;
    }

    // 2. Fetch/rasterize page 1 asynchronously
    if (mounted) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }

    try {
      final thumb = await service.getPdfThumbnail(
        widget.documentId,
        attachmentId: widget.attachmentId,
      );
      if (mounted) {
        setState(() {
          _thumbnailBytes = thumb;
          _isLoading = false;
          _hasError = thumb == null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final border = widget.borderRadius ?? BorderRadius.circular(10);

    Widget content;
    if (_thumbnailBytes != null && _thumbnailBytes!.isNotEmpty) {
      Widget image = Image.memory(
        _thumbnailBytes!,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        errorBuilder: (context, error, stackTrace) => _buildFallbackCard(),
      );

      image = ClipRRect(borderRadius: border, child: image);

      // Add "Page 1 • PDF" badge in bottom right corner
      content = Stack(
        alignment: Alignment.bottomRight,
        children: [
          Center(child: image),
          Positioned(
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.picture_as_pdf_rounded,
                    size: 11,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.pageCount > 1
                        ? 'Page 1 of ${widget.pageCount}'
                        : 'Page 1 • PDF',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    } else if (_isLoading) {
      content = _buildLoadingPlaceholder();
    } else {
      content = _buildFallbackCard();
    }

    Widget result = ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: widget.maxHeight ?? 260.0,
        maxWidth: widget.maxWidth ?? double.infinity,
      ),
      child: content,
    );

    if (widget.onTap != null) {
      result = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: border,
          child: result,
        ),
      );
    }

    return result;
  }

  Widget _buildLoadingPlaceholder() {
    return Container(
      width: widget.width ?? double.infinity,
      height: widget.height ?? 160.0,
      decoration: BoxDecoration(
        color: AppColors.filePdf.withValues(alpha: 0.05),
        borderRadius: widget.borderRadius ?? BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.filePdf,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Rendering Page 1...',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackCard() {
    return Container(
      width: widget.width ?? double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.filePdf.withValues(alpha: 0.06),
        borderRadius: widget.borderRadius ?? BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.filePdf.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.picture_as_pdf_rounded,
              size: 28,
              color: AppColors.filePdf,
            ),
          ),
          const SizedBox(height: 10),
          if (widget.fileName != null) ...[
            Text(
              widget.fileName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            _hasError ? 'PDF Document • Tap to view' : 'PDF Document',
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

