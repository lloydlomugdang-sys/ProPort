import 'package:flutter/material.dart';
import '../models/portfolio_image_element.dart';
import '../models/portfolio_shape_element.dart';
import '../models/portfolio_text_element.dart';

class ClipboardLogic {
  static PortfolioTextElement copyTextElement(
    PortfolioTextElement element,
  ) {
    return element.copyWith(
      id: -1,
    );
  }

  static PortfolioShapeElement copyShapeElement(
    PortfolioShapeElement element,
  ) {
    return element.copyWith(
      id: -1,
    );
  }

  static PortfolioImageElement copyImageElement(
    PortfolioImageElement element,
  ) {
    return element.copyWith(
      id: -1,
    );
  }

  static PortfolioTextElement pasteTextElement({
    required PortfolioTextElement copiedElement,
    required int newId,
    required int newZIndex,
    required double canvasWidth,
    required double canvasHeight,
  }) {
    final pastedX = (copiedElement.position.dx + 16).clamp(
      0.0,
      canvasWidth - copiedElement.width,
    );

    final pastedY = (copiedElement.position.dy + 16).clamp(
      0.0,
      canvasHeight - copiedElement.height,
    );

    return copiedElement.copyWith(
      id: newId,
      position: Offset(
        pastedX.toDouble(),
        pastedY.toDouble(),
      ),
      zIndex: newZIndex,
    );
  }

  static PortfolioShapeElement pasteShapeElement({
    required PortfolioShapeElement copiedElement,
    required int newId,
    required int newZIndex,
    required double canvasWidth,
    required double canvasHeight,
  }) {
    final pastedX = (copiedElement.position.dx + 16).clamp(
      0.0,
      canvasWidth - copiedElement.width,
    );

    final pastedY = (copiedElement.position.dy + 16).clamp(
      0.0,
      canvasHeight - copiedElement.height,
    );

    return copiedElement.copyWith(
      id: newId,
      position: Offset(
        pastedX.toDouble(),
        pastedY.toDouble(),
      ),
      zIndex: newZIndex,
    );
  }

  static PortfolioImageElement pasteImageElement({
    required PortfolioImageElement copiedElement,
    required int newId,
    required int newZIndex,
    required double canvasWidth,
    required double canvasHeight,
  }) {
    final pastedX = (copiedElement.position.dx + 16).clamp(
      0.0,
      canvasWidth - copiedElement.width,
    );

    final pastedY = (copiedElement.position.dy + 16).clamp(
      0.0,
      canvasHeight - copiedElement.height,
    );

    return copiedElement.copyWith(
      id: newId,
      position: Offset(
        pastedX.toDouble(),
        pastedY.toDouble(),
      ),
      zIndex: newZIndex,
    );
  }
}