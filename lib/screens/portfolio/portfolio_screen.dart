import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import 'models/portfolio_page_data.dart';
import 'models/portfolio_save_result.dart';
import 'portfolio_editor_screen.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  final List<PortfolioSaveResult> portfolios = [
    const PortfolioSaveResult(
      title: 'Student Career Portfolio',
      sizeLabel: 'A4 Portrait',
      pages: [
        PortfolioPageData(
          id: 1,
          textElements: [],
          shapeElements: [],
          imageElements: [],
        ),
      ],
      uploadedImagePaths: [],
    ),
    const PortfolioSaveResult(
      title: 'Internship Portfolio',
      sizeLabel: 'Square',
      pages: [
        PortfolioPageData(
          id: 1,
          textElements: [],
          shapeElements: [],
          imageElements: [],
        ),
      ],
      uploadedImagePaths: [],
    ),
  ];

  void _showPortfolioSizePicker(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 22),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Choose Portfolio Size',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                        },
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  const Text(
                    'Select the canvas size before designing your portfolio.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 20),

                  _sizeOption(
                    dialogContext: dialogContext,
                    parentContext: context,
                    title: 'A4 Portrait',
                    sizeText: '210 × 297 mm',
                    subtitle: 'Best for resume-style portfolios.',
                    icon: Icons.stay_current_portrait_outlined,
                    canvasType: PortfolioCanvasType.a4Portrait,
                  ),

                  _sizeOption(
                    dialogContext: dialogContext,
                    parentContext: context,
                    title: 'A4 Landscape',
                    sizeText: '297 × 210 mm',
                    subtitle: 'Best for wide visual layouts.',
                    icon: Icons.stay_current_landscape_outlined,
                    canvasType: PortfolioCanvasType.a4Landscape,
                  ),

                  _sizeOption(
                    dialogContext: dialogContext,
                    parentContext: context,
                    title: 'Square',
                    sizeText: '1080 × 1080 px',
                    subtitle: 'Balanced layout for compact portfolio pages.',
                    icon: Icons.crop_square_outlined,
                    canvasType: PortfolioCanvasType.square,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sizeOption({
    required BuildContext dialogContext,
    required BuildContext parentContext,
    required String title,
    required String sizeText,
    required String subtitle,
    required IconData icon,
    required PortfolioCanvasType canvasType,
  }) {
    return InkWell(
      onTap: () {
        Navigator.pop(dialogContext);
        _openNewPortfolioEditor(parentContext, canvasType);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.input,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: AppColors.white,
                size: 24,
              ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 3),

                  Text(
                    sizeText,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            const Icon(
              Icons.arrow_forward_ios,
              color: AppColors.textSecondary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openNewPortfolioEditor(
    BuildContext context,
    PortfolioCanvasType canvasType,
  ) async {
    final result = await Navigator.push<PortfolioSaveResult>(
      context,
      MaterialPageRoute(
        builder: (_) => PortfolioEditorScreen(
          canvasType: canvasType,
        ),
      ),
    );

    if (!mounted || result == null) return;

    setState(() {
      portfolios.insert(0, result);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${result.title}" saved to All Portfolios.'),
      ),
    );
  }

  PortfolioCanvasType _canvasTypeFromSize(String size) {
    if (size == 'A4 Landscape') {
      return PortfolioCanvasType.a4Landscape;
    }

    if (size == 'Square') {
      return PortfolioCanvasType.square;
    }

    return PortfolioCanvasType.a4Portrait;
  }

  Future<void> _openExistingPortfolio(
    BuildContext context,
    int index,
  ) async {
    final portfolio = portfolios[index];

    final result = await Navigator.push<PortfolioSaveResult>(
      context,
      MaterialPageRoute(
        builder: (_) => PortfolioEditorScreen(
          canvasType: _canvasTypeFromSize(portfolio.sizeLabel),
          initialTitle: portfolio.title,
          initialPages: portfolio.pages
              .map((page) => page.deepCopy())
              .toList(),
          initialUploadedImagePaths: List<String>.from(
            portfolio.uploadedImagePaths,
          ),
        ),
      ),
    );

    if (!mounted || result == null) return;

    setState(() {
      portfolios[index] = result;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${result.title}" updated.'),
      ),
    );
  }

  int _totalTexts(PortfolioSaveResult portfolio) {
    return portfolio.pages.fold(
      0,
      (total, page) => total + page.textElements.length,
    );
  }

  int _totalShapes(PortfolioSaveResult portfolio) {
    return portfolio.pages.fold(
      0,
      (total, page) => total + page.shapeElements.length,
    );
  }

  int _totalImages(PortfolioSaveResult portfolio) {
    return portfolio.pages.fold(
      0,
      (total, page) => total + page.imageElements.length,
    );
  }

  Widget _portfolioCard({
    required BuildContext context,
    required int index,
    required PortfolioSaveResult portfolio,
  }) {
    return InkWell(
      onTap: () {
        _openExistingPortfolio(context, index);
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              height: 135,
              decoration: BoxDecoration(
                color: const Color(0xFF587A80),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.dashboard_customize_outlined,
                color: AppColors.white,
                size: 46,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              portfolio.title,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 4),

            Text(
              portfolio.sizeLabel,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              '${portfolio.pages.length} page(s) • '
              '${_totalTexts(portfolio)} text • '
              '${_totalShapes(portfolio)} shapes • '
              '${_totalImages(portfolio)} images',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addPortfolioButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: () {
          _showPortfolioSizePicker(context);
        },
        icon: const Icon(Icons.add, size: 21),
        label: const Text(
          'Add Portfolio',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.input,
          foregroundColor: AppColors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Portfolio Builder',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 6),

              const Text(
                'Design your portfolio now.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 26),

              _addPortfolioButton(context),

              const SizedBox(height: 30),

              const Text(
                'All Portfolios',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 14),

              ...List.generate(
                portfolios.length,
                (index) => _portfolioCard(
                  context: context,
                  index: index,
                  portfolio: portfolios[index],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}