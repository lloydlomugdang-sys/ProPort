import 'package:flutter/material.dart';
import '../models/portfolio_shape_element.dart';

class ShapeElementLogic {
  static PortfolioShapeElement createShapeElement({
    required int id,
    required int zIndex,
    required PortfolioShapeType shapeType,
    required double canvasWidth,
    required double canvasHeight,
  }) {
    final bool isCircle = shapeType == PortfolioShapeType.circle;

    final double width = isCircle ? 74.0 : 96.0;
    final double height = isCircle ? 74.0 : 62.0;

    return PortfolioShapeElement(
      id: id,
      type: shapeType,
      width: width,
      height: height,
      color: const Color(0xFF8EB4BB),
      zIndex: zIndex,
      position: Offset(
        (canvasWidth - width) / 2,
        (canvasHeight - height) / 2,
      ),
    );
  }

  static List<PortfolioShapeElement> updatePosition({
    required List<PortfolioShapeElement> elements,
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

  static List<PortfolioShapeElement> updateSize({
    required List<PortfolioShapeElement> elements,
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

  static List<PortfolioShapeElement> updateColor({
    required List<PortfolioShapeElement> elements,
    required int elementId,
    required Color color,
  }) {
    return elements.map((element) {
      if (element.id == elementId) {
        return element.copyWith(color: color);
      }
      return element;
    }).toList();
  }

  static PortfolioShapeElement duplicateShapeElement({
    required PortfolioShapeElement element,
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

  static List<PortfolioShapeElement> deleteShapeElement({
    required List<PortfolioShapeElement> elements,
    required int elementId,
  }) {
    return elements
        .where((element) => element.id != elementId)
        .toList();
  }
}