import 'package:flutter/material.dart';
import '../models/portfolio_text_element.dart';

class TextElementLogic {
  static PortfolioTextElement createTextElement({
    required int id,
    required int zIndex,
    required double canvasWidth,
    required double canvasHeight,
  }) {
    return PortfolioTextElement(
      id: id,
      text: 'Add your text',
      position: Offset(
        (canvasWidth - 150) / 2,
        (canvasHeight - 56) / 2,
      ),
      width: 150,
      height: 56,
      fontSize: 14,
      isBold: true,
      isItalic: false,
      isUnderline: false,
      fontFamily: 'sans-serif',
      textAlign: TextAlign.center,
      color: Colors.black,
      zIndex: zIndex,
    );
  }

  static List<PortfolioTextElement> updatePosition({
    required List<PortfolioTextElement> elements,
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

  static List<PortfolioTextElement> updateSize({
    required List<PortfolioTextElement> elements,
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

  static List<PortfolioTextElement> updateText({
    required List<PortfolioTextElement> elements,
    required int elementId,
    required String newText,
  }) {
    return elements.map((element) {
      if (element.id == elementId) {
        return element.copyWith(text: newText);
      }
      return element;
    }).toList();
  }

  static List<PortfolioTextElement> updateColor({
    required List<PortfolioTextElement> elements,
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

  static List<PortfolioTextElement> updateFontFamily({
    required List<PortfolioTextElement> elements,
    required int elementId,
    required String fontFamily,
  }) {
    return elements.map((element) {
      if (element.id == elementId) {
        return element.copyWith(fontFamily: fontFamily);
      }
      return element;
    }).toList();
  }

  static List<PortfolioTextElement> decreaseFontSize({
    required List<PortfolioTextElement> elements,
    required int elementId,
  }) {
    return elements.map((element) {
      if (element.id == elementId) {
        return element.copyWith(
          fontSize: (element.fontSize - 1).clamp(8.0, 40.0),
        );
      }
      return element;
    }).toList();
  }

  static List<PortfolioTextElement> increaseFontSize({
    required List<PortfolioTextElement> elements,
    required int elementId,
  }) {
    return elements.map((element) {
      if (element.id == elementId) {
        return element.copyWith(
          fontSize: (element.fontSize + 1).clamp(8.0, 40.0),
        );
      }
      return element;
    }).toList();
  }

  static List<PortfolioTextElement> toggleBold({
    required List<PortfolioTextElement> elements,
    required int elementId,
  }) {
    return elements.map((element) {
      if (element.id == elementId) {
        return element.copyWith(
          isBold: !element.isBold,
        );
      }
      return element;
    }).toList();
  }

  static List<PortfolioTextElement> toggleItalic({
    required List<PortfolioTextElement> elements,
    required int elementId,
  }) {
    return elements.map((element) {
      if (element.id == elementId) {
        return element.copyWith(
          isItalic: !element.isItalic,
        );
      }
      return element;
    }).toList();
  }

  static List<PortfolioTextElement> toggleUnderline({
    required List<PortfolioTextElement> elements,
    required int elementId,
  }) {
    return elements.map((element) {
      if (element.id == elementId) {
        return element.copyWith(
          isUnderline: !element.isUnderline,
        );
      }
      return element;
    }).toList();
  }

  static List<PortfolioTextElement> setAlignment({
    required List<PortfolioTextElement> elements,
    required int elementId,
    required TextAlign alignment,
  }) {
    return elements.map((element) {
      if (element.id == elementId) {
        return element.copyWith(
          textAlign: alignment,
        );
      }
      return element;
    }).toList();
  }

  static PortfolioTextElement duplicateTextElement({
    required PortfolioTextElement element,
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

  static List<PortfolioTextElement> deleteTextElement({
    required List<PortfolioTextElement> elements,
    required int elementId,
  }) {
    return elements
        .where((element) => element.id != elementId)
        .toList();
  }
}