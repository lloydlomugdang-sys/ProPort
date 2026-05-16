import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';

class TextElementActions extends StatelessWidget {
  final bool isVisible;
  final double fontSize;
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final String fontFamily;
  final TextAlign textAlign;

  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onMore;
  final VoidCallback onDecreaseFont;
  final VoidCallback onIncreaseFont;
  final VoidCallback onToggleBold;
  final VoidCallback onToggleItalic;
  final VoidCallback onToggleUnderline;
  final VoidCallback onPickFontStyle;
  final VoidCallback onAlignLeft;
  final VoidCallback onAlignCenter;
  final VoidCallback onAlignRight;
  final VoidCallback onPickColor;

  const TextElementActions({
    super.key,
    required this.isVisible,
    required this.fontSize,
    required this.isBold,
    required this.isItalic,
    required this.isUnderline,
    required this.fontFamily,
    required this.textAlign,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onMore,
    required this.onDecreaseFont,
    required this.onIncreaseFont,
    required this.onToggleBold,
    required this.onToggleItalic,
    required this.onToggleUnderline,
    required this.onPickFontStyle,
    required this.onAlignLeft,
    required this.onAlignCenter,
    required this.onAlignRight,
    required this.onPickColor,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      color: const Color(0xFF294B51),
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _mainActionButton(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  onPressed: onEdit,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _mainActionButton(
                  icon: Icons.copy_outlined,
                  label: 'Duplicate',
                  onPressed: onDuplicate,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 15),
                    label: const Text(
                      'Delete',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 38,
                height: 34,
                child: ElevatedButton(
                  onPressed: onMore,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surface,
                    foregroundColor: AppColors.white,
                    elevation: 0,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Icon(
                    Icons.more_horiz,
                    size: 19,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text(
                      'Font Size',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    _smallIconButton(
                      icon: Icons.remove,
                      onPressed: onDecreaseFont,
                    ),
                    Container(
                      width: 40,
                      alignment: Alignment.center,
                      child: Text(
                        fontSize.toStringAsFixed(0),
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _smallIconButton(
                      icon: Icons.add,
                      onPressed: onIncreaseFont,
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                Row(
                  children: [
                    Expanded(
                      child: _wideMiniButton(
                        icon: Icons.font_download_outlined,
                        label: _getShortFontLabel(fontFamily),
                        onPressed: onPickFontStyle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _wideMiniButton(
                        icon: Icons.palette_outlined,
                        label: 'Text Color',
                        onPressed: onPickColor,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                Row(
                  children: [
                    Expanded(
                      child: _toggleButton(
                        icon: Icons.format_bold,
                        isActive: isBold,
                        onPressed: onToggleBold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _toggleButton(
                        icon: Icons.format_italic,
                        isActive: isItalic,
                        onPressed: onToggleItalic,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _toggleButton(
                        icon: Icons.format_underline,
                        isActive: isUnderline,
                        onPressed: onToggleUnderline,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                Row(
                  children: [
                    Expanded(
                      child: _toggleButton(
                        icon: Icons.format_align_left,
                        isActive: textAlign == TextAlign.left,
                        onPressed: onAlignLeft,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _toggleButton(
                        icon: Icons.format_align_center,
                        isActive: textAlign == TextAlign.center,
                        onPressed: onAlignCenter,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _toggleButton(
                        icon: Icons.format_align_right,
                        isActive: textAlign == TextAlign.right,
                        onPressed: onAlignRight,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getShortFontLabel(String fontFamily) {
    switch (fontFamily) {
      case 'serif':
        return 'Serif';
      case 'monospace':
        return 'Monospace';
      case 'cursive':
        return 'Cursive';
      default:
        return 'Sans Serif';
    }
  }

  Widget _mainActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 34,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 15),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _wideMiniButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 34,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 15),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.card,
          foregroundColor: AppColors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _smallIconButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 30,
      height: 30,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.card,
          foregroundColor: AppColors.white,
          elevation: 0,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Icon(icon, size: 17),
      ),
    );
  }

  Widget _toggleButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 34,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isActive ? AppColors.input : AppColors.card,
          foregroundColor: AppColors.white,
          elevation: 0,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Icon(icon, size: 17),
      ),
    );
  }
}