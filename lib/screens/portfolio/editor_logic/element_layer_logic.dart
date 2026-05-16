import 'package:flutter/material.dart';
import '../models/portfolio_image_element.dart';
import '../models/portfolio_shape_element.dart';
import '../models/portfolio_text_element.dart';

class ElementLayerLogic {
  static List<PortfolioTextElement> bringTextToFront({
    required List<PortfolioTextElement> elements,
    required int elementId,
    required int newZIndex,
  }) {
    return elements.map((element) {
      if (element.id == elementId) {
        return element.copyWith(zIndex: newZIndex);
      }

      return element;
    }).toList();
  }

  static List<PortfolioShapeElement> bringShapeToFront({
    required List<PortfolioShapeElement> elements,
    required int elementId,
    required int newZIndex,
  }) {
    return elements.map((element) {
      if (element.id == elementId) {
        return element.copyWith(zIndex: newZIndex);
      }

      return element;
    }).toList();
  }

  static List<PortfolioImageElement> bringImageToFront({
    required List<PortfolioImageElement> elements,
    required int elementId,
    required int newZIndex,
  }) {
    return elements.map((element) {
      if (element.id == elementId) {
        return element.copyWith(zIndex: newZIndex);
      }

      return element;
    }).toList();
  }

  static List<PortfolioTextElement> sendTextToBack({
    required List<PortfolioTextElement> elements,
    required int elementId,
    required int newZIndex,
  }) {
    return elements.map((element) {
      if (element.id == elementId) {
        return element.copyWith(zIndex: newZIndex);
      }

      return element;
    }).toList();
  }

  static List<PortfolioShapeElement> sendShapeToBack({
    required List<PortfolioShapeElement> elements,
    required int elementId,
    required int newZIndex,
  }) {
    return elements.map((element) {
      if (element.id == elementId) {
        return element.copyWith(zIndex: newZIndex);
      }

      return element;
    }).toList();
  }

  static List<PortfolioImageElement> sendImageToBack({
    required List<PortfolioImageElement> elements,
    required int elementId,
    required int newZIndex,
  }) {
    return elements.map((element) {
      if (element.id == elementId) {
        return element.copyWith(zIndex: newZIndex);
      }

      return element;
    }).toList();
  }

  static Offset getAlignedPosition({
    required Offset currentPosition,
    required double elementWidth,
    required double elementHeight,
    required double canvasWidth,
    required double canvasHeight,
    required String alignment,
  }) {
    switch (alignment) {
      case 'left':
        return Offset(0, currentPosition.dy);

      case 'centerHorizontal':
        return Offset(
          (canvasWidth - elementWidth) / 2,
          currentPosition.dy,
        );

      case 'right':
        return Offset(
          canvasWidth - elementWidth,
          currentPosition.dy,
        );

      case 'top':
        return Offset(currentPosition.dx, 0);

      case 'centerVertical':
        return Offset(
          currentPosition.dx,
          (canvasHeight - elementHeight) / 2,
        );

      case 'bottom':
        return Offset(
          currentPosition.dx,
          canvasHeight - elementHeight,
        );

      default:
        return currentPosition;
    }
  }

  static List<PortfolioTextElement> alignTextElement({
    required List<PortfolioTextElement> elements,
    required int elementId,
    required double canvasWidth,
    required double canvasHeight,
    required String alignment,
  }) {
    return elements.map((element) {
      if (element.id == elementId) {
        final alignedPosition = getAlignedPosition(
          currentPosition: element.position,
          elementWidth: element.width,
          elementHeight: element.height,
          canvasWidth: canvasWidth,
          canvasHeight: canvasHeight,
          alignment: alignment,
        );

        return element.copyWith(position: alignedPosition);
      }

      return element;
    }).toList();
  }

  static List<PortfolioShapeElement> alignShapeElement({
    required List<PortfolioShapeElement> elements,
    required int elementId,
    required double canvasWidth,
    required double canvasHeight,
    required String alignment,
  }) {
    return elements.map((element) {
      if (element.id == elementId) {
        final alignedPosition = getAlignedPosition(
          currentPosition: element.position,
          elementWidth: element.width,
          elementHeight: element.height,
          canvasWidth: canvasWidth,
          canvasHeight: canvasHeight,
          alignment: alignment,
        );

        return element.copyWith(position: alignedPosition);
      }

      return element;
    }).toList();
  }

  static List<PortfolioImageElement> alignImageElement({
    required List<PortfolioImageElement> elements,
    required int elementId,
    required double canvasWidth,
    required double canvasHeight,
    required String alignment,
  }) {
    return elements.map((element) {
      if (element.id == elementId) {
        final alignedPosition = getAlignedPosition(
          currentPosition: element.position,
          elementWidth: element.width,
          elementHeight: element.height,
          canvasWidth: canvasWidth,
          canvasHeight: canvasHeight,
          alignment: alignment,
        );

        return element.copyWith(position: alignedPosition);
      }

      return element;
    }).toList();
  }
}