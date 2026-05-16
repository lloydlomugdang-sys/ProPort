import 'portfolio_image_element.dart';
import 'portfolio_shape_element.dart';
import 'portfolio_text_element.dart';

class PortfolioPageData {
  final int id;
  final List<PortfolioTextElement> textElements;
  final List<PortfolioShapeElement> shapeElements;
  final List<PortfolioImageElement> imageElements;

  const PortfolioPageData({
    required this.id,
    required this.textElements,
    required this.shapeElements,
    required this.imageElements,
  });

  PortfolioPageData copyWith({
    int? id,
    List<PortfolioTextElement>? textElements,
    List<PortfolioShapeElement>? shapeElements,
    List<PortfolioImageElement>? imageElements,
  }) {
    return PortfolioPageData(
      id: id ?? this.id,
      textElements: textElements ?? this.textElements,
      shapeElements: shapeElements ?? this.shapeElements,
      imageElements: imageElements ?? this.imageElements,
    );
  }

  PortfolioPageData deepCopy() {
    return PortfolioPageData(
      id: id,
      textElements: textElements
          .map((element) => element.copyWith())
          .toList(),
      shapeElements: shapeElements
          .map((element) => element.copyWith())
          .toList(),
      imageElements: imageElements
          .map((element) => element.copyWith())
          .toList(),
    );
  }
}