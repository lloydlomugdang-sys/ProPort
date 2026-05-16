import 'package:flutter/material.dart';

class PortfolioTextElement {
  final int id;
  String text;
  Offset position;
  double width;
  double height;
  double fontSize;
  bool isBold;
  bool isItalic;
  bool isUnderline;
  String fontFamily;
  TextAlign textAlign;
  Color color;
  int zIndex;

  PortfolioTextElement({
    required this.id,
    required this.text,
    required this.position,
    required this.width,
    required this.height,
    required this.fontSize,
    required this.isBold,
    this.isItalic = false,
    this.isUnderline = false,
    this.fontFamily = 'sans-serif',
    required this.textAlign,
    required this.color,
    required this.zIndex,
  });

  PortfolioTextElement copyWith({
    int? id,
    String? text,
    Offset? position,
    double? width,
    double? height,
    double? fontSize,
    bool? isBold,
    bool? isItalic,
    bool? isUnderline,
    String? fontFamily,
    TextAlign? textAlign,
    Color? color,
    int? zIndex,
  }) {
    return PortfolioTextElement(
      id: id ?? this.id,
      text: text ?? this.text,
      position: position ?? this.position,
      width: width ?? this.width,
      height: height ?? this.height,
      fontSize: fontSize ?? this.fontSize,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      isUnderline: isUnderline ?? this.isUnderline,
      fontFamily: fontFamily ?? this.fontFamily,
      textAlign: textAlign ?? this.textAlign,
      color: color ?? this.color,
      zIndex: zIndex ?? this.zIndex,
    );
  }
}