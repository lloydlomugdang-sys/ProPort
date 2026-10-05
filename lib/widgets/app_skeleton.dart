import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Single-parent shimmer coordinator that sweeps a gradient across child skeleton widgets.
/// Uses a single [AnimationController] per skeleton subtree to minimize CPU/GPU load.
/// Automatically respects [MediaQuery.disableAnimationsOf] for accessibility.
class AppShimmer extends StatefulWidget {
  const AppShimmer({
    super.key,
    required this.child,
    this.baseColor = const Color(0xFFE5EEF3),
    this.highlightColor = const Color(0xFFF7FAFC),
    this.duration = const Duration(milliseconds: 1400),
  });

  final Widget child;
  final Color baseColor;
  final Color highlightColor;
  final Duration duration;

  @override
  State<AppShimmer> createState() => _AppShimmerState();
}

class _AppShimmerState extends State<AppShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (disableAnimations) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (disableAnimations) {
      return _ShimmerColorScope(
        color: widget.baseColor,
        child: widget.child,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final double value = _controller.value;
            // Sweep gradient from -1.0 to 2.0 to give smooth entry and exit
            final double start = (value * 3.0) - 1.0;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: const [0.0, 0.5, 1.0],
              transform: _SlidingGradientTransform(slidePercent: start),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: _ShimmerColorScope(
        color: widget.baseColor,
        child: widget.child,
      ),
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({required this.slidePercent});

  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0.0, 0.0);
  }
}

class _ShimmerColorScope extends InheritedWidget {
  const _ShimmerColorScope({
    required this.color,
    required super.child,
  });

  final Color color;

  static Color of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_ShimmerColorScope>();
    return scope?.color ?? const Color(0xFFE5EEF3);
  }

  @override
  bool updateShouldNotify(_ShimmerColorScope oldWidget) => color != oldWidget.color;
}

// ─── Base Primitives ─────────────────────────────────────────────────────────

/// A rounded rectangle placeholder box that adopts the ambient [AppShimmer] gradient.
class AppSkeletonBox extends StatelessWidget {
  const AppSkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.margin,
  });

  final double? width;
  final double? height;
  final BorderRadiusGeometry borderRadius;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final color = _ShimmerColorScope.of(context);
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: color,
        borderRadius: borderRadius,
      ),
    );
  }
}

/// A text line placeholder with natural height and rounded ends.
class AppSkeletonText extends StatelessWidget {
  const AppSkeletonText({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
    this.margin,
  });

  final double? width;
  final double height;
  final BorderRadiusGeometry borderRadius;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return AppSkeletonBox(
      width: width,
      height: height,
      borderRadius: borderRadius,
      margin: margin,
    );
  }
}

/// A container card mirroring GradPort's card container style.
class AppSkeletonCard extends StatelessWidget {
  const AppSkeletonCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: borderRadius,
        border: Border.all(color: AppColors.cardBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ─── Compound Skeletons ───────────────────────────────────────────────────────

/// Skeleton row mimicking [FolderRowItem].
class FolderRowSkeleton extends StatelessWidget {
  const FolderRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: const [
          AppSkeletonBox(
            width: 38,
            height: 38,
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          SizedBox(width: 14),
          Expanded(
            child: AppSkeletonText(
              width: 120,
              height: 15,
            ),
          ),
          SizedBox(width: 12),
          AppSkeletonBox(
            width: 28,
            height: 20,
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          SizedBox(width: 8),
          AppSkeletonBox(
            width: 14,
            height: 14,
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
        ],
      ),
    );
  }
}

/// Skeleton category section with header and grouped folder rows inside a card.
class CategoryGroupSkeleton extends StatelessWidget {
  const CategoryGroupSkeleton({
    super.key,
    this.rowCount = 2,
  });

  final int rowCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: AppSkeletonText(
              width: 140,
              height: 16,
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
          ),
          AppSkeletonCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: List.generate(rowCount, (index) {
                final isLast = index == rowCount - 1;
                return Column(
                  children: [
                    const FolderRowSkeleton(),
                    if (!isLast)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        indent: 16,
                        endIndent: 16,
                        color: AppColors.divider,
                      ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-page skeleton for [FilesScreen].
class FilesScreenSkeleton extends StatelessWidget {
  const FilesScreenSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          100 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            AppSkeletonBox(
              height: 48,
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
            SizedBox(height: 22),
            CategoryGroupSkeleton(rowCount: 3),
            CategoryGroupSkeleton(rowCount: 2),
            CategoryGroupSkeleton(rowCount: 2),
          ],
        ),
      ),
    );
  }
}

/// Multi-line paragraph skeleton for the OCR extracted text area.
class OcrTextSkeleton extends StatelessWidget {
  const OcrTextSkeleton({
    super.key,
    this.lineCount = 6,
  });

  final int lineCount;

  static const _widths = [1.0, 0.92, 0.85, 0.96, 0.70, 0.90, 0.82, 0.65];

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < lineCount; i++) ...[
              FractionallySizedBox(
                widthFactor: _widths[i % _widths.length],
                child: const AppSkeletonText(height: 13),
              ),
              if (i < lineCount - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

/// Skeleton for a document preview card thumbnail.
class DocumentPreviewSkeleton extends StatelessWidget {
  const DocumentPreviewSkeleton({
    super.key,
    this.height = 180,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  final double height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: AppSkeletonBox(
        height: height,
        borderRadius: borderRadius,
      ),
    );
  }
}

/// Skeleton for the [PortfolioPreviewScreen] sheet.
class PortfolioPreviewSkeleton extends StatelessWidget {
  const PortfolioPreviewSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header lines
            const Center(child: AppSkeletonText(width: 220, height: 18)),
            const SizedBox(height: 8),
            const Center(child: AppSkeletonText(width: 180, height: 12)),
            const SizedBox(height: 14),
            const Center(child: AppSkeletonText(width: 140, height: 16)),
            const SizedBox(height: 24),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 20),

            // Student info lines
            const AppSkeletonText(width: 150, height: 15),
            const SizedBox(height: 12),
            for (var i = 0; i < 4; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    AppSkeletonText(width: 100, height: 12),
                    AppSkeletonText(width: 140, height: 12),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),

            // Sections Included table
            const AppSkeletonText(width: 140, height: 15),
            const SizedBox(height: 12),
            AppSkeletonCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          AppSkeletonText(width: 120, height: 13),
                          AppSkeletonBox(
                            width: 24,
                            height: 18,
                            borderRadius: BorderRadius.all(Radius.circular(6)),
                          ),
                        ],
                      ),
                    ),
                    if (i < 2) const Divider(height: 1, color: AppColors.divider),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Document detail card
            const AppSkeletonText(width: 140, height: 15),
            const SizedBox(height: 12),
            AppSkeletonCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  AppSkeletonBox(
                    height: 140,
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  SizedBox(height: 10),
                  AppSkeletonText(width: 160, height: 14),
                  SizedBox(height: 6),
                  AppSkeletonText(width: 100, height: 11),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
