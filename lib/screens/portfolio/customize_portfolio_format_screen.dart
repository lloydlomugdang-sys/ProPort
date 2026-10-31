import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../services/api_client.dart';
import '../../services/portfolio_scope.dart';
import '../../services/portfolio_template.dart';
import '../../widgets/grad_app_bar.dart';
import '../../widgets/primary_button.dart';
import 'models/portfolio_models.dart';

class _EditableSection {
  _EditableSection({
    required this.key,
    required this.defaultLabel,
    required String initialLabel,
    required this.enabled,
    required this.generateCreativeTitle,
    required String initialCreativeTitle,
  })  : labelController = TextEditingController(text: initialLabel),
        creativeTitleController =
            TextEditingController(text: initialCreativeTitle);

  final String key;
  final String defaultLabel;
  final TextEditingController labelController;
  bool enabled;
  bool generateCreativeTitle;
  final TextEditingController creativeTitleController;

  void dispose() {
    labelController.dispose();
    creativeTitleController.dispose();
  }
}

/// Screen allowing students to customize their portfolio template:
/// section order, section enabled/disabled, section display label,
/// Creative Title per section, Table of Contents, and Reset to Default.
class CustomizePortfolioFormatScreen extends StatefulWidget {
  const CustomizePortfolioFormatScreen({
    super.key,
    required this.portfolio,
    this.baseTemplate,
  });

  final PortfolioRecord portfolio;
  final PortfolioTemplate? baseTemplate;

  @override
  State<CustomizePortfolioFormatScreen> createState() =>
      _CustomizePortfolioFormatScreenState();
}

class _CustomizePortfolioFormatScreenState
    extends State<CustomizePortfolioFormatScreen> {
  PortfolioTemplate? _baseTemplate;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _includeTableOfContents = true;
  List<_EditableSection> _sections = [];

  @override
  void initState() {
    super.initState();
    if (widget.baseTemplate != null) {
      _baseTemplate = widget.baseTemplate;
      _initFromTemplate(widget.baseTemplate!);
      _loading = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_baseTemplate == null) {
      _loadTemplate();
    }
  }

  Future<void> _loadTemplate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final portfolioService = PortfolioScope.maybeOf(context);
      if (portfolioService == null) throw const FormatException();
      final template = await portfolioService.loadTemplate();
      if (!mounted) return;
      _baseTemplate = template;
      _initFromTemplate(template);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is ApiException
              ? e.message
              : 'Unable to load portfolio template. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _initFromTemplate(PortfolioTemplate base) {
    for (final s in _sections) {
      s.dispose();
    }
    final overrides = widget.portfolio.info.templateOverrides;
    _includeTableOfContents =
        overrides?.includeTableOfContents ?? base.includeTableOfContents;

    final effective = base.withOverrides(overrides);
    final creativeTitles = widget.portfolio.info.creativeTitles;

    _sections = effective.sections.map((sec) {
      final baseSec = base.section(sec.key);
      return _EditableSection(
        key: sec.key,
        defaultLabel: baseSec?.label ?? sec.label,
        initialLabel: sec.label,
        enabled: sec.enabled,
        generateCreativeTitle: sec.generateCreativeTitle,
        initialCreativeTitle: creativeTitles[sec.key] ?? '',
      );
    }).toList();
  }

  @override
  void dispose() {
    for (final s in _sections) {
      s.dispose();
    }
    super.dispose();
  }

  void _moveSection(int index, int delta) {
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= _sections.length) return;
    setState(() {
      final item = _sections.removeAt(index);
      _sections.insert(newIndex, item);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final sectionOverrides = <PortfolioSectionOverride>[];
      final creativeTitles = <String, String>{};

      for (var i = 0; i < _sections.length; i++) {
        final s = _sections[i];
        final trimmedLabel = s.labelController.text.trim();
        final trimmedCreative = s.creativeTitleController.text.trim();

        sectionOverrides.add(
          PortfolioSectionOverride(
            key: s.key,
            order: i,
            label: trimmedLabel.isNotEmpty ? trimmedLabel : s.defaultLabel,
            enabled: s.enabled,
            generateCreativeTitle: s.generateCreativeTitle,
          ),
        );

        if (s.enabled && s.generateCreativeTitle && trimmedCreative.isNotEmpty) {
          creativeTitles[s.key] = trimmedCreative;
        }
      }

      final overrides = PortfolioTemplateOverride(
        includeTableOfContents: _includeTableOfContents,
        sections: sectionOverrides,
      );

      final service = PortfolioScope.of(context);
      final updated = await service.saveCustomization(
        widget.portfolio.id,
        templateOverrides: overrides,
        creativeTitles: creativeTitles,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Portfolio format saved successfully.'),
          backgroundColor: AppColors.primary,
        ),
      );
      Navigator.pop(context, updated);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is ApiException
              ? e.message
              : 'Failed to save format customization. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('confirm-reset-dialog'),
        title: const Text('Reset to Default Template?'),
        content: const Text(
          'This will restore the standard section order, labels, and settings prescribed by the default institutional template. Your uploaded documents and responses will NOT be deleted.',
        ),
        actions: [
          TextButton(
            key: const Key('confirm-reset-cancel-btn'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirm-reset-btn'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Reset to Default',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final service = PortfolioScope.of(context);
      final updated = await service.saveCustomization(
        widget.portfolio.id,
        resetTemplateOverrides: true,
        creativeTitles: const {},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Portfolio format reset to default template.'),
          backgroundColor: AppColors.primary,
        ),
      );
      Navigator.pop(context, updated);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is ApiException
              ? e.message
              : 'Failed to reset template. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: GradBackAppBar(
        title: 'Customize Format',
        onBack: () => Navigator.pop(context),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 540),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Informative Banner ────────────────────────────────
                        _buildBanner(),
                        const SizedBox(height: 16),

                        // ── Error Banner ──────────────────────────────────────
                        if (_error != null) ...[
                          Container(
                            key: const Key('customize-format-error'),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppColors.danger.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: AppColors.danger,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.danger,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // ── Table of Contents Setting Card ───────────────────
                        _buildTocCard(),
                        const SizedBox(height: 16),

                        // ── Section Ordering & Options Card ───────────────────
                        _buildSectionsHeader(),
                        const SizedBox(height: 12),

                        for (var i = 0; i < _sections.length; i++) ...[
                          _buildSectionItem(i, _sections[i]),
                          const SizedBox(height: 12),
                        ],

                        const SizedBox(height: 16),

                        // ── Action Buttons ────────────────────────────────────
                        PrimaryButton(
                          key: const Key('save-customization-btn'),
                          label: _saving ? 'Saving...' : 'Save Customization',
                          isLoading: _saving,
                          onPressed: () {
                            if (!_saving) _save();
                          },
                          height: 50,
                        ),
                        const SizedBox(height: 12),

                        OutlinedButton.icon(
                          key: const Key('reset-customization-btn'),
                          icon: const Icon(Icons.restore, size: 18),
                          label: const Text('Reset to Default Template'),
                          onPressed: _saving ? null : _confirmReset,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: BorderSide(
                              color: AppColors.danger.withValues(alpha: 0.5),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Customize section order, labels, and titles for this portfolio. Changing the portfolio format does not delete uploaded documents.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTocCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Table of Contents',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Include a Table of Contents page in the compiled document.',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            key: const Key('toc-toggle'),
            value: _includeTableOfContents,
            activeThumbColor: AppColors.primary,
            onChanged: _saving
                ? null
                : (val) {
                    setState(() => _includeTableOfContents = val);
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionsHeader() {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Text(
          'Portfolio Sections',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        Text(
          '${_sections.where((s) => s.enabled).length} of ${_sections.length} enabled',
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionItem(int index, _EditableSection section) {
    final isFirst = index == 0;
    final isLast = index == _sections.length - 1;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: section.enabled
              ? AppColors.cardBorder
              : AppColors.divider.withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header row: Order number, Reorder arrows, Enable switch
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            decoration: BoxDecoration(
              color: section.enabled
                  ? AppColors.primary.withValues(alpha: 0.04)
                  : AppColors.background,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
              border: Border(
                bottom: BorderSide(
                  color: AppColors.divider.withValues(alpha: 0.6),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: section.enabled
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '#${index + 1}',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    section.defaultLabel,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: section.enabled
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  key: Key('move-up-section-${section.key}'),
                  icon: const Icon(Icons.arrow_upward, size: 20),
                  tooltip: 'Move Up',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: (!isFirst && !_saving)
                      ? () => _moveSection(index, -1)
                      : null,
                ),
                IconButton(
                  key: Key('move-down-section-${section.key}'),
                  icon: const Icon(Icons.arrow_downward, size: 20),
                  tooltip: 'Move Down',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: (!isLast && !_saving)
                      ? () => _moveSection(index, 1)
                      : null,
                ),
                Switch(
                  key: Key('enable-toggle-section-${section.key}'),
                  value: section.enabled,
                  activeThumbColor: AppColors.primary,
                  onChanged: _saving
                      ? null
                      : (val) {
                          setState(() => section.enabled = val);
                        },
                ),
              ],
            ),
          ),

          // Section body: Display label text field & creative title settings
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: Key('label-input-section-${section.key}'),
                  controller: section.labelController,
                  enabled: section.enabled && !_saving,
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: 'Display Label',
                    hintText: section.defaultLabel,
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  style: GoogleFonts.poppins(fontSize: 13),
                ),
                const SizedBox(height: 10),

                // Creative title toggle
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Section Creative Title Page',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: section.enabled
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Switch(
                      key: Key('creative-title-toggle-section-${section.key}'),
                      value: section.generateCreativeTitle,
                      activeThumbColor: AppColors.primary,
                      onChanged: (section.enabled && !_saving)
                          ? (val) {
                              setState(() => section.generateCreativeTitle = val);
                            }
                          : null,
                    ),
                  ],
                ),

                if (section.enabled && section.generateCreativeTitle) ...[
                  const SizedBox(height: 6),
                  TextField(
                    key: Key('creative-title-input-section-${section.key}'),
                    controller: section.creativeTitleController,
                    enabled: !_saving,
                    maxLength: 200,
                    decoration: InputDecoration(
                      labelText: 'Creative Title Text',
                      hintText: 'e.g. MY ${section.defaultLabel.toUpperCase()}',
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    style: GoogleFonts.poppins(fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
