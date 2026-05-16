import 'package:flutter/material.dart';

enum PortfolioShapeType {
  rectangle,
  circle,
}

class PortfolioShapeElement {
  final int id;
  final PortfolioShapeType type;
  Offset position;
  double width;
  double height;
  Color color;
  int zIndex;

  PortfolioShapeElement({
    required this.id,
    required this.type,
    required this.position,
    required this.width,
    required this.height,
    required this.color,
    required this.zIndex,
  });

  PortfolioShapeElement copyWith({
    int? id,
    PortfolioShapeType? type,
    Offset? position,
    double? width,
    double? height,
    Color? color,
    int? zIndex,
  }) {
    return PortfolioShapeElement(
      id: id ?? this.id,
      type: type ?? this.type,
      position: position ?? this.position,
      width: width ?? this.width,
      height: height ?? this.height,
      color: color ?? this.color,
      zIndex: zIndex ?? this.zIndex,
    );
  }
}