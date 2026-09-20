import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/document_scope.dart';

/// Renders an authentic uploaded document image using [DocumentService].
/// Provides asynchronous retrieval, in-memory cache lookup, loading placeholder,
/// error fallback, and optional pinch-to-zoom full-screen preview.
class DocumentImagePreview extends StatefulWidget {
  const DocumentImagePreview({
    super.key,
    required this.documentId,
    this.attachmentId,
    this.fit = BoxFit.contain,
    this.maxHeight,
    this.maxWidth,
    this.width,
    this.height,
    this.borderRadius,
    this.showFullScreenOnTap = false,
    this.fallbackWidget,
    this.heroTag,
    this.cacheWidth,
    this.cacheHeight,
  });

  final String documentId;
  final String? attachmentId;
  final BoxFit fit;
  final double? maxHeight;
  final double? maxWidth;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final bool showFullScreenOnTap;
  final Widget? fallbackWidget;
  final String? heroTag;
  final int? cacheWidth;
  final int? cacheHeight;

  @override
  State<DocumentImagePreview> createState() => _DocumentImagePreviewState();
}

class _DocumentImagePreviewState extends State<DocumentImagePreview> {
  Uint8List? _bytes;
  bool _isLoading = false;
  bool _hasError = false;
  bool _loadInitiated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadInitiated) {
      _loadInitiated = true;
      _loadContent();
    }
  }

  @override
  void didUpdateWidget(DocumentImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documentId != widget.documentId ||
        oldWidget.attachmentId != widget.attachmentId) {
      _bytes = null;
      _isLoading = false;
      _hasError = false;
      _loadContent();
    }
  }

  Future<void> _loadContent() async {
    final service = DocumentScope.of(context);
    // 1. Check synchronous cache first
    final cached = service.getCachedContent(
      widget.documentId,
      attachmentId: widget.attachmentId,
    );
    if (cached != null) {
      if (mounted) {
        setState(() {
          _bytes = cached;
          _isLoading = false;
          _hasError = false;
        });
      }
      return;
    }

    // 2. Fetch asynchronously
    if (mounted) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }

    try {
      final bytes = await service.getDocumentContent(
        widget.documentId,
        attachmentId: widget.attachmentId,
      );
      if (mounted) {
        setState(() {
          _bytes = bytes;
          _isLoading = false;
          _hasError = false;
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

  void _openFullScreen(BuildContext context, Uint8List bytes) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (dialogContext) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black.withValues(alpha: 0.6),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Close',
              onPressed: () => Navigator.pop(dialogContext),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final border = widget.borderRadius ?? BorderRadius.circular(12);

    Widget content;
    if (_bytes != null && _bytes!.isNotEmpty) {
      Widget image = Image.memory(
        _bytes!,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        cacheWidth: widget.cacheWidth,
        cacheHeight: widget.cacheHeight,
        errorBuilder: (context, error, stackTrace) => _buildFallback(),
      );

      if (widget.heroTag != null) {
        image = Hero(tag: widget.heroTag!, child: image);
      }

      if (widget.showFullScreenOnTap) {
        image = GestureDetector(
          onTap: () => _openFullScreen(context, _bytes!),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: image,
          ),
        );
      }

      content = ClipRRect(borderRadius: border, child: image);
    } else if (_isLoading) {
      content = _buildLoading();
    } else {
      content = _buildFallback();
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: widget.maxHeight ?? double.infinity,
        maxWidth: widget.maxWidth ?? double.infinity,
      ),
      child: content,
    );
  }

  Widget _buildLoading() {
    final double size = widget.width ?? widget.height ?? 44.0;
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.5),
        borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
      ),
      child: Center(
        child: SizedBox(
          width: (size * 0.4).clamp(16.0, 28.0),
          height: (size * 0.4).clamp(16.0, 28.0),
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildFallback() {
    if (widget.fallbackWidget != null) {
      return widget.fallbackWidget!;
    }
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: AppColors.fileImage.withValues(alpha: 0.08),
        borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
      ),
      child: Center(
        child: Icon(
          _hasError ? Icons.broken_image_outlined : Icons.image_outlined,
          color: AppColors.fileImage,
          size: 24,
        ),
      ),
    );
  }
}

/// Small, lightweight thumbnail for document lists (e.g. Files screen).
/// Loads Page 1 (primary document content) without attachmentId.
class DocumentThumbnail extends StatelessWidget {
  const DocumentThumbnail({
    super.key,
    required this.documentId,
    this.attachmentId,
    this.size = 44.0,
    this.cacheWidth = 140,
    this.cacheHeight,
  });

  final String documentId;
  final String? attachmentId;
  final double size;
  final int? cacheWidth;
  final int? cacheHeight;

  @override
  Widget build(BuildContext context) {
    return DocumentImagePreview(
      documentId: documentId,
      attachmentId: attachmentId,
      width: size,
      height: size,
      fit: BoxFit.cover,
      borderRadius: BorderRadius.circular(12),
      showFullScreenOnTap: false,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      fallbackWidget: Center(
        child: Icon(
          Icons.image_rounded,
          color: AppColors.fileImage,
          size: size * 0.55,
        ),
      ),
    );
  }
}
