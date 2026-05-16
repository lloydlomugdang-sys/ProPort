import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';

class EditorPageSection extends StatelessWidget {
  final int selectedPageIndex;
  final int pageCount;
  final ValueChanged<int> onSelectPage;
  final VoidCallback onAddPage;
  final VoidCallback onAddSection;

  const EditorPageSection({
    super.key,
    required this.selectedPageIndex,
    required this.pageCount,
    required this.onSelectPage,
    required this.onAddPage,
    required this.onAddSection,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF294B51),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              onPressed: onAddSection,
              icon: const Icon(Icons.add, size: 18),
              label: const Text(
                'Add section',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: constraints.maxWidth,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ...List.generate(
                        pageCount,
                        (index) => Padding(
                          padding: EdgeInsets.only(
                            right: index == pageCount - 1 ? 14 : 12,
                          ),
                          child: _PageThumbnail(
                            pageNumber: index + 1,
                            isSelected: selectedPageIndex == index,
                            onTap: () {
                              onSelectPage(index);
                            },
                          ),
                        ),
                      ),

                      _AddPageThumbnail(
                        onTap: onAddPage,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PageThumbnail extends StatelessWidget {
  final int pageNumber;
  final bool isSelected;
  final VoidCallback onTap;

  const _PageThumbnail({
    required this.pageNumber,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 112,
        height: 70,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.input : AppColors.border,
            width: isSelected ? 2.5 : 1.2,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              left: 7,
              bottom: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Page $pageNumber',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddPageThumbnail extends StatelessWidget {
  final VoidCallback onTap;

  const _AddPageThumbnail({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 112,
        height: 70,
        decoration: BoxDecoration(
          color: const Color(0xFF587A80),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.border,
            width: 1.2,
          ),
        ),
        child: const Center(
          child: Icon(
            Icons.add,
            color: AppColors.white,
            size: 26,
          ),
        ),
      ),
    );
  }
}