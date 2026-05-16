import 'portfolio_page_data.dart';

class PortfolioSaveResult {
  final String title;
  final String sizeLabel;
  final List<PortfolioPageData> pages;
  final List<String> uploadedImagePaths;

  const PortfolioSaveResult({
    required this.title,
    required this.sizeLabel,
    required this.pages,
    required this.uploadedImagePaths,
  });
}