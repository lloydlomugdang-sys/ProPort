// LOCATION: lib/screens/files/document_scan_review_screen.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

import '../../constants/app_colors.dart';
import '../../services/scanner/classical_cv_engine.dart';

/// Interactive review and perspective correction screen for classical camera document scanning.
///
/// Allows the student to inspect the photo, fine-tune the 4 detected boundary corners,
/// select a deterministic enhancement mode (Color, Enhanced, Grayscale, B&W),
/// and either accept the processed document or retake the photo.
class DocumentScanReviewScreen extends StatefulWidget {
  const DocumentScanReviewScreen({
    super.key,
    required this.imagePath,
    required this.initialCorners,
    this.initialMode = ScanEnhancementMode.enhanced,
  });

  final String imagePath;
  final DocumentCorners initialCorners;
  final ScanEnhancementMode initialMode;

  @override
  State<DocumentScanReviewScreen> createState() =>
      _DocumentScanReviewScreenState();
}

class _DocumentScanReviewScreenState extends State<DocumentScanReviewScreen> {
  late DocumentCorners _corners;
  late ScanEnhancementMode _selectedMode;
  bool _isProcessing = false;
  bool _adjusting = false;
  bool _hasManualCrop = false;
  int? _activeCornerIndex; // 0: TL, 1: TR, 2: BR, 3: BL

  Uint8List? _rawImageBytes;
  Uint8List? _previewBytes;
  Size? _imagePixelSize;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _corners = widget.initialCorners.isAutoDetected
        ? widget.initialCorners
        : DocumentCorners.fullImage();
    _selectedMode = widget.initialCorners.isAutoDetected
        ? widget.initialMode
        : ScanEnhancementMode.original;
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final file = File(widget.imagePath);
      if (!await file.exists()) {
        if (!mounted) return;
        setState(
          () => _errorMessage = 'The captured image could not be loaded.',
        );
        return;
      }
      final bytes = await file.readAsBytes();
      final decoded = await decodeImageFromList(bytes);
      final imageSize = Size(
        decoded.width.toDouble(),
        decoded.height.toDouble(),
      );
      decoded.dispose();
      if (!mounted) return;
      setState(() {
        _rawImageBytes = bytes;
        _imagePixelSize = imageSize;
      });
      await _refreshPreview();
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Failed to load image: ${e.toString()}');
    }
  }

  Future<bool> _refreshPreview() async {
    if (_rawImageBytes == null || _isProcessing) return false;
    setState(() {
      _isProcessing = true;
      _previewBytes = null;
    });
    try {
      final bytes = await ClassicalCvEngine.warpAndEnhanceAsync(
        WarpParams(
          imageBytes: _rawImageBytes!,
          corners: _corners,
          mode: _selectedMode,
        ),
      );
      if (!mounted) return false;
      setState(() {
        _previewBytes = bytes;
        _isProcessing = false;
      });
      return true;
    } catch (_) {
      if (!mounted) return false;
      setState(() {
        _isProcessing = false;
        _adjusting = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to process these corners. Adjust them or use the full photo.',
          ),
        ),
      );
      return false;
    }
  }

  Future<void> _previewAdjustment() async {
    if (await _refreshPreview() && mounted) {
      setState(() => _adjusting = false);
    }
  }

  Future<void> _useFullPhoto() async {
    if (_isProcessing || _rawImageBytes == null) return;
    setState(() {
      _corners = DocumentCorners.fullImage();
      _selectedMode = ScanEnhancementMode.original;
      _hasManualCrop = false;
      _adjusting = false;
    });
    await _refreshPreview();
  }

  Future<void> _onAccept() async {
    if (_previewBytes == null || _isProcessing || _adjusting) return;
    setState(() => _isProcessing = true);

    try {
      final tempDir = await getTemporaryDirectory();
      final outName = 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final outFile = File('${tempDir.path}/$outName');
      // Upload exactly the reviewed JPEG; do not warp/re-encode it a second time.
      await outFile.writeAsBytes(_previewBytes!);

      if (!mounted) return;
      Navigator.pop(context, outFile.path);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to process document corners. Please adjust corner positions.',
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
          ),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  void _onRetake() {
    if (_isProcessing) return;
    Navigator.pop(context, null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _adjusting ? 'Document Boundary' : 'Review Scan',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _onRetake,
          tooltip: 'Cancel',
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Status banner indicating detection status
            _buildDetectionStatusBanner(),

            // Interactive image and corner adjustment area
            Expanded(
              child: _errorMessage != null
                  ? Center(
                      child: Text(
                        _errorMessage!,
                        style: GoogleFonts.poppins(color: Colors.white70),
                      ),
                    )
                  : _rawImageBytes == null || _isProcessing
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : _adjusting
                  ? _buildInteractiveImageViewport()
                  : _previewBytes == null
                  ? const SizedBox.shrink()
                  : Image.memory(
                      _previewBytes!,
                      key: const Key('scan-corrected-preview'),
                      fit: BoxFit.contain,
                    ),
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: _isProcessing || _rawImageBytes == null
                      ? null
                      : _adjusting
                      ? _previewAdjustment
                      : () => setState(() => _adjusting = true),
                  child: Text(_adjusting ? 'Preview Scan' : 'Adjust corners'),
                ),
                TextButton(
                  onPressed: _isProcessing || _rawImageBytes == null
                      ? null
                      : _useFullPhoto,
                  child: const Text('Use full photo'),
                ),
              ],
            ),

            // Mode Selector
            _buildModeSelector(),

            // Bottom Actions (Retake & Accept)
            _buildBottomActionBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildDetectionStatusBanner() {
    final isAuto = _corners.isAutoDetected;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isAuto
          ? AppColors.primary.withValues(alpha: 0.25)
          : const Color(0xFFE67E22).withValues(alpha: 0.25),
      child: Row(
        children: [
          Icon(
            isAuto ? Icons.auto_awesome_rounded : Icons.touch_app_rounded,
            size: 16,
            color: isAuto ? const Color(0xFF64B5F6) : const Color(0xFFF39C12),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isAuto
                  ? 'Automatically cropped and straightened. Review before using.'
                  : _hasManualCrop
                  ? 'Manual adjustment. Preview and check all document edges.'
                  : 'No confident crop selected. Full photo kept; review or adjust corners.',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveImageViewport() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerW = constraints.maxWidth;
        final containerH = constraints.maxHeight;

        if (_imagePixelSize == null || containerW <= 0 || containerH <= 0) {
          return const SizedBox.shrink();
        }

        // Calculate fitted image dimensions maintaining aspect ratio (BoxFit.contain)
        final imgW = _imagePixelSize!.width;
        final imgH = _imagePixelSize!.height;
        final scale = math.min(containerW / imgW, containerH / imgH);
        final renderW = imgW * scale;
        final renderH = imgH * scale;
        final renderLeft = (containerW - renderW) / 2.0;
        final renderTop = (containerH - renderH) / 2.0;

        final renderRect = Rect.fromLTWH(
          renderLeft,
          renderTop,
          renderW,
          renderH,
        );

        // Map normalized corners to container coordinates
        final absTL = Offset(
          renderLeft + _corners.topLeft.dx * renderW,
          renderTop + _corners.topLeft.dy * renderH,
        );
        final absTR = Offset(
          renderLeft + _corners.topRight.dx * renderW,
          renderTop + _corners.topRight.dy * renderH,
        );
        final absBR = Offset(
          renderLeft + _corners.bottomRight.dx * renderW,
          renderTop + _corners.bottomRight.dy * renderH,
        );
        final absBL = Offset(
          renderLeft + _corners.bottomLeft.dx * renderW,
          renderTop + _corners.bottomLeft.dy * renderH,
        );

        final cornerPoints = [absTL, absTR, absBR, absBL];

        return GestureDetector(
          key: const Key('scan-corner-adjustment'),
          onPanStart: (details) {
            final touch = details.localPosition;
            const touchRadius = 36.0;
            var closestIdx = -1;
            var minDist = touchRadius;

            for (var i = 0; i < cornerPoints.length; i++) {
              final d = (cornerPoints[i] - touch).distance;
              if (d < minDist) {
                minDist = d;
                closestIdx = i;
              }
            }

            if (closestIdx != -1) {
              setState(() => _activeCornerIndex = closestIdx);
            }
          },
          onPanUpdate: (details) {
            if (_activeCornerIndex == null) return;

            final touch = details.localPosition;
            // Clamp to rendered image rect
            final clampedX = touch.dx.clamp(renderLeft, renderLeft + renderW);
            final clampedY = touch.dy.clamp(renderTop, renderTop + renderH);

            final normX = ((clampedX - renderLeft) / renderW).clamp(0.0, 1.0);
            final normY = ((clampedY - renderTop) / renderH).clamp(0.0, 1.0);
            final newNormOffset = Offset(normX, normY);

            setState(() {
              _hasManualCrop = true;
              _previewBytes = null;
              switch (_activeCornerIndex!) {
                case 0:
                  _corners = _corners.copyWith(
                    topLeft: newNormOffset,
                    isAutoDetected: false,
                  );
                  break;
                case 1:
                  _corners = _corners.copyWith(
                    topRight: newNormOffset,
                    isAutoDetected: false,
                  );
                  break;
                case 2:
                  _corners = _corners.copyWith(
                    bottomRight: newNormOffset,
                    isAutoDetected: false,
                  );
                  break;
                case 3:
                  _corners = _corners.copyWith(
                    bottomLeft: newNormOffset,
                    isAutoDetected: false,
                  );
                  break;
              }
            });
          },
          onPanEnd: (_) => setState(() => _activeCornerIndex = null),
          onPanCancel: () => setState(() => _activeCornerIndex = null),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Base image
              Center(
                child: Image.memory(
                  _rawImageBytes!,
                  width: renderW,
                  height: renderH,
                  fit: BoxFit.contain,
                ),
              ),

              // Quadrilateral outline & draggable pins overlay
              CustomPaint(
                size: Size(containerW, containerH),
                painter: _DocumentQuadPainter(
                  corners: cornerPoints,
                  renderRect: renderRect,
                  activeCornerIndex: _activeCornerIndex,
                ),
              ),

              // Loupe magnifier on active corner drag
              if (_activeCornerIndex != null)
                _buildMagnifierLoupe(
                  cornerPoints[_activeCornerIndex!],
                  containerW,
                  containerH,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMagnifierLoupe(
    Offset touchPos,
    double containerW,
    double containerH,
  ) {
    const loupeSize = 80.0;
    // Position loupe above the finger so it is not obscured
    var loupeX = touchPos.dx - loupeSize / 2;
    var loupeY = touchPos.dy - loupeSize - 30;

    // Bounds checking
    if (loupeY < 10) loupeY = touchPos.dy + 35;
    loupeX = loupeX.clamp(10.0, containerW - loupeSize - 10);

    return Positioned(
      left: loupeX,
      top: loupeY,
      child: Container(
        width: loupeSize,
        height: loupeSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 8, spreadRadius: 2),
          ],
        ),
        child: ClipOval(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Magnified image fragment
              Transform.scale(
                scale: 1.8,
                origin: Offset(
                  touchPos.dx - loupeX - loupeSize / 2,
                  touchPos.dy - loupeY - loupeSize / 2,
                ),
                child: Image.memory(_rawImageBytes!, fit: BoxFit.cover),
              ),
              // Center crosshairs
              Container(width: 14, height: 1.5, color: AppColors.primary),
              Container(width: 1.5, height: 14, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFF141414),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildModeChip('Color', ScanEnhancementMode.original),
          _buildModeChip('Enhanced', ScanEnhancementMode.enhanced),
          _buildModeChip('Grayscale', ScanEnhancementMode.grayscale),
          _buildModeChip('B&W', ScanEnhancementMode.blackAndWhite),
        ],
      ),
    );
  }

  Widget _buildModeChip(String label, ScanEnhancementMode mode) {
    final isSelected = _selectedMode == mode;
    return GestureDetector(
      onTap: _isProcessing || _rawImageBytes == null || _adjusting
          ? null
          : () async {
              if (_selectedMode == mode) return;
              setState(() => _selectedMode = mode);
              await _refreshPreview();
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white12,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.white70 : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      color: Colors.black,
      child: Row(
        children: [
          // Retake button
          Expanded(
            flex: 1,
            child: OutlinedButton.icon(
              onPressed: _isProcessing ? null : _onRetake,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                'Retake',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Accept / Use Scan button
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _isProcessing || _adjusting || _previewBytes == null
                  ? null
                  : _onAccept,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_rounded, size: 18),
              label: Text(
                _isProcessing ? 'Processing...' : 'Use Scan',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for document boundary overlay and handles.
class _DocumentQuadPainter extends CustomPainter {
  const _DocumentQuadPainter({
    required this.corners,
    required this.renderRect,
    this.activeCornerIndex,
  });

  final List<Offset> corners;
  final Rect renderRect;
  final int? activeCornerIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;

    final tl = corners[0];
    final tr = corners[1];
    final br = corners[2];
    final bl = corners[3];

    // 1. Shaded mask outside polygon
    final polyPath = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(bl.dx, bl.dy)
      ..close();

    final maskPath = Path()
      ..addRect(renderRect)
      ..addPath(polyPath, Offset.zero)
      ..fillType = PathFillType.evenOdd;

    final maskPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
    canvas.drawPath(maskPath, maskPaint);

    // 2. Document boundary line
    final linePaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(polyPath, linePaint);

    // 3. Corner handle pins
    const handleRadius = 14.0;
    const innerDotRadius = 5.0;

    for (var i = 0; i < 4; i++) {
      final p = corners[i];
      final isActive = activeCornerIndex == i;

      // Outer ring
      final outerPaint = Paint()
        ..color = isActive ? Colors.white : AppColors.primary
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p, handleRadius, outerPaint);

      // Inner dot
      final innerPaint = Paint()
        ..color = isActive ? AppColors.primary : Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p, innerDotRadius, innerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DocumentQuadPainter oldDelegate) {
    return oldDelegate.corners != corners ||
        oldDelegate.renderRect != renderRect ||
        oldDelegate.activeCornerIndex != activeCornerIndex;
  }
}
