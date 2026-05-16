import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';

class EditorBottomToolbar extends StatelessWidget {
  final int selectedToolIndex;
  final void Function(int index) onToolTap;

  const EditorBottomToolbar({
    super.key,
    required this.selectedToolIndex,
    required this.onToolTap,
  });

  static const List<Map<String, dynamic>> editorTools = [
    {
      'icon': Icons.text_fields,
      'label': 'Text',
    },
    {
      'icon': Icons.category_outlined,
      'label': 'Shapes',
    },
    {
      'icon': Icons.photo_library_outlined,
      'label': 'Camera Roll',
    },
    {
      'icon': Icons.cloud_upload_outlined,
      'label': 'Uploads',
    },
    {
      'icon': Icons.grid_view_outlined,
      'label': 'Portfolios',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: List.generate(editorTools.length, (index) {
          final tool = editorTools[index];
          final bool isSelected = selectedToolIndex == index;

          return Expanded(
            child: InkWell(
              onTap: () {
                onToolTap(index);
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 3,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.input : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      tool['icon'],
                      color: AppColors.white,
                      size: 21,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      tool['label'],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}