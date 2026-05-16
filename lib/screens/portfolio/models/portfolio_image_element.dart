import 'package:flutter/material.dart';

class PortfolioImageElement {
  final int id;
  final String imagePath;
  Offset position;
  double width;
  double height;
  int zIndex;

  PortfolioImageElement({
    required this.id,
    required this.imagePath,
    required this.position,
    required this.width,
    required this.height,
    required this.zIndex,
  });

  PortfolioImageElement copyWith({
    int? id,
    String? imagePath,
    Offset? position,
    double? width,
    double? height,
    int? zIndex,
  }) {
    return PortfolioImageElement(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      position: position ?? this.position,
      width: width ?? this.width,
      height: height ?? this.height,
      zIndex: zIndex ?? this.zIndex,
    );
  }
}