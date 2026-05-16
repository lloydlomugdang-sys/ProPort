import 'package:flutter/material.dart';
import '../models/portfolio_image_element.dart';

class ImageElementLogic {
  static PortfolioImageElement createImageElement({
    required int id,
    required int zIndex,
    required String imagePath,
    required double canvasWidth,
    required double canvasHeight,
  }) {
    const double defaultWidth = 120;
    const double defaultHeight = 100;

    return PortfolioImageElement(
      id: id,
      imagePath: imagePath,
      position: Offset(
        (canvasWidth - defaultWidth) / 2,
        (canvasHeight - defaultHeight) / 2,
      ),
      width: defaultWidth,
      height: defaultHeight,
      zIndex: zIndex,
    );
  }

  static List<PortfolioImageElement> updatePosition({
    required List<PortfolioImageElement> elements,
    required int elementId,
    required Offset newPosition,
  }) {
    return elements.map((element) {
      if (element.id == elementId) {
        return element.copyWith(position: newPosition);
      }

      return element;
    }).toList();
  }

  static List<PortfolioImageElement> updateSize({
    required List<PortfolioImageElement> elements,
    required int elementId,
    required Size newSize,
  }) {
    return elements.map((element) {
      if (element.id == elementId) {
        return element.copyWith(
          width: newSize.width,
          height: newSize.height,
        );
      }

      return element;
    }).toList();
  }

  static PortfolioImageElement duplicateImageElement({
    required PortfolioImageElement element,
    required int newId,
    required int newZIndex,
    required double canvasWidth,
    required double canvasHeight,
  }) {
    final duplicatedX = (element.position.dx + 12).clamp(
      0.0,
      canvasWidth - element.width,
    );

    final duplicatedY = (element.position.dy + 12).clamp(
      0.0,
      canvasHeight - element.height,
    );

    return element.copyWith(
      id: newId,
      position: Offset(
        duplicatedX.toDouble(),
        duplicatedY.toDouble(),
      ),
      zIndex: newZIndex,
    );
  }

  static List<PortfolioImageElement> deleteImageElement({
    required List<PortfolioImageElement> elements,
    required int elementId,
  }) {
    return elements
        .where((element) => element.id != elementId)
        .toList();
  }
}