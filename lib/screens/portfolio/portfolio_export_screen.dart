// LOCATION: lib/screens/portfolio/portfolio_export_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../constants/app_colors.dart';
import '../../services/document_scope.dart';
import '../../services/portfolio_export_service.dart';
import '../../services/portfolio_scope.dart';
import '../../widgets/grad_app_bar.dart';
import '../../widgets/primary_button.dart';

import '../main_screen.dart';
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
      final documents = DocumentScope.of(context);
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentScope(
            documentService: documents,
            child: PortfolioPreviewScreen(
              portfolioInfo: widget.portfolioInfo,
              exportFormat: _exportedFile?.format,
            ),
          ),
        ),
      );
    } finally {
      _previewOpen = false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Result container
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildExportResult() => Container(
    key: const Key('portfolio-export-success'),
    margin: const EdgeInsets.only(top: 20),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.statusCompleteBg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: AppColors.success.withValues(alpha: 0.30),
        width: 1.2,
      ),
      boxShadow: [
        BoxShadow(
          color: AppColors.success.withValues(alpha: 0.08),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            color: AppColors.success,
            size: 26,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Portfolio file created',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.statusCompleteText,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _exportedFile!.name,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _coverageNote!,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Temporary copy. Use Share to send or save it.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: Builder(
            builder: (buttonContext) => ElevatedButton.icon(
              onPressed: _isSharing ? null : () => _onShare(buttonContext),
              icon: const Icon(Icons.share_rounded, size: 18),
              label: Text(_isSharing ? 'Sharing...' : 'Share'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: _roundedBorder(),
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _onPreview,
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('Preview Portfolio'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.cardBorder, width: 1.2),
              shape: _roundedBorder(),
              padding: const EdgeInsets.symmetric(vertical: 12),
              textStyle: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: () => MainScreen.returnToDashboard(context),
            icon: const Icon(Icons.dashboard_rounded, size: 18),
            label: const Text('Back to Dashboard'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              shape: _roundedBorder(),
              padding: const EdgeInsets.symmetric(vertical: 10),
              textStyle: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  static RoundedRectangleBorder _roundedBorder() =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));

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
                      const SizedBox(height: 24),

                      PrimaryButton(
                        label: 'Export Portfolio',
                        isLoading: _isExporting,
                        onPressed: _onExport,
                        height: 52,
                      ),
                      if (_isExporting) ...[
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(AppColors.primary),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Generating portfolio...',
                              key: const Key('portfolio-export-progress'),
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.danger.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 18,
                                color: AppColors.danger,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  key: const Key('portfolio-export-error'),
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: AppColors.danger,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
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
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Export Portfolio',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),

          Text(
            'Choose the file format you want to export.',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Export your saved title page and current document details. Original uploaded images and PDF pages are not embedded.',
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: AppColors.textMuted,
              height: 1.4,
            ),
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
