// LOCATION: lib/screens/portfolio/portfolio_export_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../services/document_scope.dart';
import '../../services/portfolio_export_service.dart';
import '../../services/portfolio_scope.dart';
import '../../widgets/grad_app_bar.dart';

import 'models/portfolio_models.dart';
import 'portfolio_preview_screen.dart';
import 'widgets/export_option_card.dart';
import 'widgets/step_indicator.dart';

/// Screen 3 of 3 — Export Portfolio.
/// Lets the user choose PDF or DOCX, then opens the Portfolio Preview screen.
class PortfolioExportScreen extends StatefulWidget {
  const PortfolioExportScreen({super.key, required this.portfolioInfo});

  final PortfolioInfo portfolioInfo;

  @override
  State<PortfolioExportScreen> createState() => _PortfolioExportScreenState();
}

class _PortfolioExportScreenState extends State<PortfolioExportScreen>
    with SingleTickerProviderStateMixin {
  ExportFormat _selectedFormat = ExportFormat.pdf;
  bool _previewOpen = false;
  bool _isExporting = false;
  bool _isSharing = false;
  String? _error;
  String? _coverageNote;
  PortfolioExportFile? _exportedFile;

  late final AnimationController _entranceCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    _fadeAnim = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );

    _slideAnim = Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceCtrl,
            curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
          ),
        );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entranceCtrl.forward();
    });
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Export action
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _onExport() async {
    if (_isExporting || _previewOpen || _isSharing) return;
    final documents = DocumentScope.of(context);
    final exporter = PortfolioScope.exporterOf(context);
    setState(() {
      _isExporting = true;
      _error = null;
      _exportedFile = null;
    });
    try {
      await documents.load(force: true);
      if (!mounted) return;
      final content = PortfolioExportContent.fromDocuments(
        widget.portfolioInfo,
        documents,
      );
      final file = await exporter.generate(content, _selectedFormat);
      if (!mounted) return;
      if (!documents.hasLoadedDocuments) {
        throw const PortfolioExportException(
          'Your session changed. Please sign in again.',
        );
      }
      setState(() {
        _exportedFile = file;
        _coverageNote = content.coverageNote;
      });
    } catch (error) {
      if (mounted) setState(() => _error = portfolioExportError(error));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _onShare(BuildContext buttonContext) async {
    final file = _exportedFile;
    if (file == null || _isSharing || _isExporting) return;
    final box = buttonContext.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      _isSharing = true;
      _error = null;
    });
    try {
      await PortfolioScope.exporterOf(context).share(file, origin);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Unable to share the file. Please try again or export a new copy.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _onPreview() async {
    if (_previewOpen || _isExporting) return;
    _previewOpen = true;
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => PortfolioPreviewScreen(
            portfolioInfo: widget.portfolioInfo,
            exportFormat: _exportedFile?.format,
          ),
        ),
      );
    } finally {
      _previewOpen = false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Preview dialog
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildExportResult() => Column(
    key: const Key('portfolio-export-success'),
    children: [
      const SizedBox(height: 16),
      Text('Portfolio file created', style: AppTextStyles.h4),
      Text(
        _exportedFile!.name,
        textAlign: TextAlign.center,
        style: AppTextStyles.bodySmall,
      ),
      Text(
        _coverageNote!,
        textAlign: TextAlign.center,
        style: AppTextStyles.labelSmall,
      ),
      Text(
        'Temporary copy. Use Share to send or save it.',
        style: AppTextStyles.labelSmall,
      ),
      Builder(
        builder: (buttonContext) => TextButton.icon(
          onPressed: _isSharing ? null : () => _onShare(buttonContext),
          icon: const Icon(Icons.share_outlined),
          label: Text(_isSharing ? 'Sharing...' : 'Share'),
        ),
      ),
      TextButton(onPressed: _onPreview, child: const Text('Preview Portfolio')),
    ],
  );

  // ─────────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: GradBackAppBar(
        title: 'Generate Portfolio',
        onBack: () => Navigator.pop(context),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    children: [
                      _buildExportCard(),
                      const SizedBox(height: 28),

                      _ExportButton(
                        isLoading: _isExporting,
                        onPressed: _onExport,
                      ),
                      if (_isExporting) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Generating portfolio...',
                          key: Key('portfolio-export-progress'),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          key: const Key('portfolio-export-error'),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.danger,
                          ),
                        ),
                      ],
                      if (_exportedFile != null) _buildExportResult(),
                    ],
                  ),
                ),
              ),

              _buildStepBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExportCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Export Portfolio', style: AppTextStyles.h3),
          const SizedBox(height: 4),

          Text(
            'Choose the file format you want to export.',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Export your saved title page and current document details. Original uploaded images and PDF pages are not embedded.',
            style: AppTextStyles.labelSmall,
          ),
          const SizedBox(height: 20),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: IntrinsicHeight(
                  child: ExportOptionCard(
                    format: ExportFormat.pdf,
                    isSelected: _selectedFormat == ExportFormat.pdf,
                    onTap: () => _selectFormat(ExportFormat.pdf),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: IntrinsicHeight(
                  child: ExportOptionCard(
                    format: ExportFormat.docx,
                    isSelected: _selectedFormat == ExportFormat.docx,
                    onTap: () => _selectFormat(ExportFormat.docx),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _selectFormat(ExportFormat format) {
    if (_isExporting || _isSharing || format == _selectedFormat) return;
    setState(() {
      _selectedFormat = format;
      _exportedFile = null;
      _error = null;
    });
  }

  Widget _buildStepBar() {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: const StepIndicatorLight(currentStep: 3),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────────
// Export button
// ───────────────────────────────────────────────────────────────────────────────
class _ExportButton extends StatefulWidget {
  const _ExportButton({required this.onPressed, this.isLoading = false});

  final VoidCallback onPressed;
  final bool isLoading;

  @override
  State<_ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends State<_ExportButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 180),
    );

    _scale = Tween<double>(
      begin: 1.0,
      end: 0.97,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) => _ctrl.reverse(),
      onTapCancel: () => _ctrl.reverse(),
      onTap: widget.isLoading ? null : widget.onPressed,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    'Export Portfolio',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
