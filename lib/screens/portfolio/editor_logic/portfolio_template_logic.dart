import 'package:flutter/material.dart';
import '../models/portfolio_shape_element.dart';
import '../models/portfolio_text_element.dart';

enum PortfolioTemplateType {
  blank,
  studentProfile,
  projectShowcase,
}

class PortfolioTemplateResult {
  final List<PortfolioTextElement> textElements;
  final List<PortfolioShapeElement> shapeElements;
  final int nextTextElementId;
  final int nextShapeElementId;
  final int nextFrontZIndex;

  const PortfolioTemplateResult({
    required this.textElements,
    required this.shapeElements,
    required this.nextTextElementId,
    required this.nextShapeElementId,
    required this.nextFrontZIndex,
  });
}

class PortfolioTemplateLogic {
  static PortfolioTemplateResult buildTemplate({
    required PortfolioTemplateType type,
    required double canvasWidth,
    required double canvasHeight,
  }) {
    switch (type) {
      case PortfolioTemplateType.blank:
        return const PortfolioTemplateResult(
          textElements: [],
          shapeElements: [],
          nextTextElementId: 1,
          nextShapeElementId: 1,
          nextFrontZIndex: 1,
        );

      case PortfolioTemplateType.studentProfile:
        return _buildStudentProfileTemplate(
          canvasWidth: canvasWidth,
          canvasHeight: canvasHeight,
        );

      case PortfolioTemplateType.projectShowcase:
        return _buildProjectShowcaseTemplate(
          canvasWidth: canvasWidth,
          canvasHeight: canvasHeight,
        );
    }
  }

  static PortfolioTemplateResult _buildStudentProfileTemplate({
    required double canvasWidth,
    required double canvasHeight,
  }) {
    int nextTextId = 1;
    int nextShapeId = 1;
    int nextZIndex = 1;

    final textElements = <PortfolioTextElement>[];
    final shapeElements = <PortfolioShapeElement>[];

    const double left = 14;
    const double top = 16;

    final double profileSize =
        (canvasWidth * 0.22).clamp(44.0, 56.0).toDouble();

    final double nameX = left + profileSize + 10;
    final double nameWidth =
        (canvasWidth - nameX - 14).clamp(90.0, canvasWidth).toDouble();

    final double aboutTitleY = top + profileSize + 18;
    final double aboutBodyY = aboutTitleY + 20;
    final double skillsTitleY = aboutBodyY + 56;
    final double chipsY = skillsTitleY + 20;

    shapeElements.add(
      PortfolioShapeElement(
        id: nextShapeId++,
        type: PortfolioShapeType.circle,
        position: const Offset(left, top),
        width: profileSize,
        height: profileSize,
        color: const Color(0xFF8EB4BB),
        zIndex: nextZIndex++,
      ),
    );

    textElements.add(
      PortfolioTextElement(
        id: nextTextId++,
        text: 'Your Name',
        position: Offset(nameX, top + 3),
        width: nameWidth,
        height: 28,
        fontSize: 16,
        isBold: true,
        textAlign: TextAlign.left,
        color: Colors.black,
        zIndex: nextZIndex++,
      ),
    );

    textElements.add(
      PortfolioTextElement(
        id: nextTextId++,
        text: 'College Student | Aspiring Professional',
        position: Offset(nameX, top + 30),
        width: nameWidth,
        height: 24,
        fontSize: 9,
        isBold: false,
        textAlign: TextAlign.left,
        color: Colors.black87,
        zIndex: nextZIndex++,
      ),
    );

    textElements.add(
      PortfolioTextElement(
        id: nextTextId++,
        text: 'About Me',
        position: Offset(left, aboutTitleY),
        width: canvasWidth - 28,
        height: 22,
        fontSize: 12,
        isBold: true,
        textAlign: TextAlign.left,
        color: Colors.black,
        zIndex: nextZIndex++,
      ),
    );

    textElements.add(
      PortfolioTextElement(
        id: nextTextId++,
        text: 'Write a short introduction about yourself, your goals, and your strengths.',
        position: Offset(left, aboutBodyY),
        width: canvasWidth - 28,
        height: 50,
        fontSize: 9,
        isBold: false,
        textAlign: TextAlign.left,
        color: Colors.black87,
        zIndex: nextZIndex++,
      ),
    );

    textElements.add(
      PortfolioTextElement(
        id: nextTextId++,
        text: 'Key Skills',
        position: Offset(left, skillsTitleY),
        width: canvasWidth - 28,
        height: 22,
        fontSize: 12,
        isBold: true,
        textAlign: TextAlign.left,
        color: Colors.black,
        zIndex: nextZIndex++,
      ),
    );

    final double chipWidth = ((canvasWidth - 48) / 3).clamp(40.0, 72.0);

    for (int index = 0; index < 3; index++) {
      shapeElements.add(
        PortfolioShapeElement(
          id: nextShapeId++,
          type: PortfolioShapeType.rectangle,
          position: Offset(
            left + (index * (chipWidth + 10)),
            chipsY,
          ),
          width: chipWidth.toDouble(),
          height: 22,
          color: const Color(0xFFD9E8EA),
          zIndex: nextZIndex++,
        ),
      );
    }

    return PortfolioTemplateResult(
      textElements: textElements,
      shapeElements: shapeElements,
      nextTextElementId: nextTextId,
      nextShapeElementId: nextShapeId,
      nextFrontZIndex: nextZIndex,
    );
  }

  static PortfolioTemplateResult _buildProjectShowcaseTemplate({
    required double canvasWidth,
    required double canvasHeight,
  }) {
    int nextTextId = 1;
    int nextShapeId = 1;
    int nextZIndex = 1;

    final textElements = <PortfolioTextElement>[];
    final shapeElements = <PortfolioShapeElement>[];

    const double left = 16;
    const double top = 18;

    final double heroHeight =
        (canvasHeight * 0.30).clamp(54.0, 86.0).toDouble();

    final double heroY = top + 54;
    final double projectTitleY = heroY + heroHeight + 12;
    final double bodyY = projectTitleY + 24;

    textElements.add(
      PortfolioTextElement(
        id: nextTextId++,
        text: 'Project Showcase',
        position: const Offset(left, top),
        width: canvasWidth - 32,
        height: 28,
        fontSize: 16,
        isBold: true,
        textAlign: TextAlign.left,
        color: Colors.black,
        zIndex: nextZIndex++,
      ),
    );

    textElements.add(
      PortfolioTextElement(
        id: nextTextId++,
        text: 'Selected works and portfolio highlights',
        position: const Offset(left, top + 28),
        width: canvasWidth - 32,
        height: 22,
        fontSize: 9,
        isBold: false,
        textAlign: TextAlign.left,
        color: Colors.black87,
        zIndex: nextZIndex++,
      ),
    );

    shapeElements.add(
      PortfolioShapeElement(
        id: nextShapeId++,
        type: PortfolioShapeType.rectangle,
        position: Offset(left, heroY),
        width: canvasWidth - 32,
        height: heroHeight,
        color: const Color(0xFFD9E8EA),
        zIndex: nextZIndex++,
      ),
    );

    textElements.add(
      PortfolioTextElement(
        id: nextTextId++,
        text: 'Project Title',
        position: Offset(left, projectTitleY),
        width: canvasWidth - 32,
        height: 24,
        fontSize: 13,
        isBold: true,
        textAlign: TextAlign.left,
        color: Colors.black,
        zIndex: nextZIndex++,
      ),
    );

    textElements.add(
      PortfolioTextElement(
        id: nextTextId++,
        text: 'Describe the project, your role, and the key skills used.',
        position: Offset(left, bodyY),
        width: canvasWidth - 32,
        height: 48,
        fontSize: 9,
        isBold: false,
        textAlign: TextAlign.left,
        color: Colors.black87,
        zIndex: nextZIndex++,
      ),
    );

    return PortfolioTemplateResult(
      textElements: textElements,
      shapeElements: shapeElements,
      nextTextElementId: nextTextId,
      nextShapeElementId: nextShapeId,
      nextFrontZIndex: nextZIndex,
    );
  }
}