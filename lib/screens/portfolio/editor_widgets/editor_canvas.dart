import 'dart:io';

import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';
import '../models/portfolio_image_element.dart';
import '../models/portfolio_shape_element.dart';
import '../models/portfolio_text_element.dart';

class EditorCanvas extends StatelessWidget {
  final String canvasLabel;
  final String canvasMeasurement;
  final double canvasWidth;
  final double canvasHeight;

  final List<PortfolioTextElement> textElements;
  final List<PortfolioShapeElement> shapeElements;
  final List<PortfolioImageElement> imageElements;

  final int? selectedTextElementId;
  final int? selectedShapeElementId;
  final int? selectedImageElementId;

  final VoidCallback onCanvasTap;

  final void Function(int elementId) onSelectTextElement;
  final void Function(int elementId, Offset newPosition) onMoveTextElement;
  final void Function(int elementId, Size newSize) onResizeTextElement;

  final void Function(int elementId) onSelectShapeElement;
  final void Function(int elementId, Offset newPosition) onMoveShapeElement;
  final void Function(int elementId, Size newSize) onResizeShapeElement;

  final void Function(int elementId) onSelectImageElement;
  final void Function(int elementId, Offset newPosition) onMoveImageElement;
  final void Function(int elementId, Size newSize) onResizeImageElement;

  const EditorCanvas({
    super.key,
    required this.canvasLabel,
    required this.canvasMeasurement,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.textElements,
    required this.shapeElements,
    required this.imageElements,
    required this.selectedTextElementId,
    required this.selectedShapeElementId,
    required this.selectedImageElementId,
    required this.onCanvasTap,
    required this.onSelectTextElement,
    required this.onMoveTextElement,
    required this.onResizeTextElement,
    required this.onSelectShapeElement,
    required this.onMoveShapeElement,
    required this.onResizeShapeElement,
    required this.onSelectImageElement,
    required this.onMoveImageElement,
    required this.onResizeImageElement,
  });

  Widget _resizeHandle() {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: AppColors.white,
          width: 1.5,
        ),
      ),
      child: const Icon(
        Icons.open_in_full,
        color: AppColors.white,
        size: 11,
      ),
    );
  }

  Widget _buildShapeElement(PortfolioShapeElement element) {
    final bool isSelected = selectedShapeElementId == element.id;

    return Positioned(
      left: element.position.dx,
      top: element.position.dy,
      child: GestureDetector(
        onTap: () {
          onSelectShapeElement(element.id);
        },
        onPanUpdate: (details) {
          final updatedX = (element.position.dx + details.delta.dx).clamp(
            0.0,
            canvasWidth - element.width,
          );

          final updatedY = (element.position.dy + details.delta.dy).clamp(
            0.0,
            canvasHeight - element.height,
          );

          onMoveShapeElement(
            element.id,
            Offset(
              updatedX.toDouble(),
              updatedY.toDouble(),
            ),
          );
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: element.width,
              height: element.height,
              decoration: BoxDecoration(
                color: element.color,
                shape: element.type == PortfolioShapeType.circle
                    ? BoxShape.circle
                    : BoxShape.rectangle,
                borderRadius: element.type == PortfolioShapeType.rectangle
                    ? BorderRadius.circular(8)
                    : null,
                border: Border.all(
                  color: isSelected ? AppColors.input : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            if (isSelected)
              Positioned(
                right: -8,
                bottom: -8,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    if (element.type == PortfolioShapeType.circle) {
                      final growth =
                          details.delta.dx.abs() > details.delta.dy.abs()
                              ? details.delta.dx
                              : details.delta.dy;

                      final newSize = (element.width + growth).clamp(
                        40.0,
                        canvasWidth - element.position.dx,
                      );

                      final maxAllowedHeight =
                          canvasHeight - element.position.dy;

                      final finalSize = newSize.clamp(
                        40.0,
                        maxAllowedHeight,
                      );

                      onResizeShapeElement(
                        element.id,
                        Size(
                          finalSize.toDouble(),
                          finalSize.toDouble(),
                        ),
                      );
                    } else {
                      final newWidth = (element.width + details.delta.dx).clamp(
                        40.0,
                        canvasWidth - element.position.dx,
                      );

                      final newHeight =
                          (element.height + details.delta.dy).clamp(
                        40.0,
                        canvasHeight - element.position.dy,
                      );

                      onResizeShapeElement(
                        element.id,
                        Size(
                          newWidth.toDouble(),
                          newHeight.toDouble(),
                        ),
                      );
                    }
                  },
                  child: _resizeHandle(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextElement(PortfolioTextElement element) {
    final bool isSelected = selectedTextElementId == element.id;

    return Positioned(
      left: element.position.dx,
      top: element.position.dy,
      child: GestureDetector(
        onTap: () {
          onSelectTextElement(element.id);
        },
        onPanUpdate: (details) {
          final updatedX = (element.position.dx + details.delta.dx).clamp(
            0.0,
            canvasWidth - element.width,
          );

          final updatedY = (element.position.dy + details.delta.dy).clamp(
            0.0,
            canvasHeight - element.height,
          );

          onMoveTextElement(
            element.id,
            Offset(
              updatedX.toDouble(),
              updatedY.toDouble(),
            ),
          );
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: element.width,
              height: element.height,
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFEAF3F4)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected ? AppColors.input : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Align(
                alignment: Alignment.center,
                child: SizedBox(
                  width: double.infinity,
                  child: Text(
                    element.text,
                    textAlign: element.textAlign,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: element.color,
                      fontSize: element.fontSize,
                      fontFamily: element.fontFamily,
                      fontWeight:
                          element.isBold ? FontWeight.bold : FontWeight.normal,
                      fontStyle: element.isItalic
                          ? FontStyle.italic
                          : FontStyle.normal,
                      decoration: element.isUnderline
                          ? TextDecoration.underline
                          : TextDecoration.none,
                      decorationColor: element.color,
                      decorationThickness: 2,
                    ),
                  ),
                ),
              ),
            ),
            if (isSelected)
              Positioned(
                right: -8,
                bottom: -8,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    final newWidth = (element.width + details.delta.dx).clamp(
                      90.0,
                      canvasWidth - element.position.dx,
                    );

                    final newHeight = (element.height + details.delta.dy).clamp(
                      44.0,
                      canvasHeight - element.position.dy,
                    );

                    onResizeTextElement(
                      element.id,
                      Size(
                        newWidth.toDouble(),
                        newHeight.toDouble(),
                      ),
                    );
                  },
                  child: _resizeHandle(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageElement(PortfolioImageElement element) {
    final bool isSelected = selectedImageElementId == element.id;

    return Positioned(
      left: element.position.dx,
      top: element.position.dy,
      child: GestureDetector(
        onTap: () {
          onSelectImageElement(element.id);
        },
        onPanUpdate: (details) {
          final updatedX = (element.position.dx + details.delta.dx).clamp(
            0.0,
            canvasWidth - element.width,
          );

          final updatedY = (element.position.dy + details.delta.dy).clamp(
            0.0,
            canvasHeight - element.height,
          );

          onMoveImageElement(
            element.id,
            Offset(
              updatedX.toDouble(),
              updatedY.toDouble(),
            ),
          );
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: element.width,
              height: element.height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected ? AppColors.input : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Image.file(
                  File(element.imagePath),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            if (isSelected)
              Positioned(
                right: -8,
                bottom: -8,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    final newWidth = (element.width + details.delta.dx).clamp(
                      60.0,
                      canvasWidth - element.position.dx,
                    );

                    final newHeight = (element.height + details.delta.dy).clamp(
                      60.0,
                      canvasHeight - element.position.dy,
                    );

                    onResizeImageElement(
                      element.id,
                      Size(
                        newWidth.toDouble(),
                        newHeight.toDouble(),
                      ),
                    );
                  },
                  child: _resizeHandle(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canvasLayers = <_CanvasLayer>[
      ...shapeElements.map(
        (shape) => _CanvasLayer(
          zIndex: shape.zIndex,
          child: _buildShapeElement(shape),
        ),
      ),
      ...imageElements.map(
        (image) => _CanvasLayer(
          zIndex: image.zIndex,
          child: _buildImageElement(image),
        ),
      ),
      ...textElements.map(
        (text) => _CanvasLayer(
          zIndex: text.zIndex,
          child: _buildTextElement(text),
        ),
      ),
    ]..sort((a, b) => a.zIndex.compareTo(b.zIndex));

    return Expanded(
      child: Container(
        width: double.infinity,
        color: const Color(0xFF294B51),
        child: Column(
          children: [
            const SizedBox(height: 18),
            Text(
              '$canvasLabel • $canvasMeasurement',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: onCanvasTap,
              child: Container(
                width: canvasWidth,
                height: canvasHeight,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Stack(
                  children: canvasLayers.map((layer) => layer.child).toList(),
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _CanvasLayer {
  final int zIndex;
  final Widget child;

  const _CanvasLayer({
    required this.zIndex,
    required this.child,
  });
}