import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';

class EditorTopBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onMenu;
  final String title;

  const EditorTopBar({
    super.key,
    required this.onBack,
    required this.onUndo,
    required this.onRedo,
    required this.onMenu,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(
            color: AppColors.border,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.home_outlined,
              color: AppColors.white,
              size: 21,
            ),
          ),

          IconButton(
            onPressed: onUndo,
            icon: const Icon(
              Icons.undo,
              color: AppColors.white,
              size: 21,
            ),
          ),

          IconButton(
            onPressed: onRedo,
            icon: const Icon(
              Icons.redo,
              color: AppColors.white,
              size: 21,
            ),
          ),

          const Spacer(),

          IconButton(
            onPressed: onMenu,
            icon: const Icon(
              Icons.more_horiz,
              color: AppColors.white,
              size: 24,
            ),
          ),

          const SizedBox(width: 2),

          Flexible(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}