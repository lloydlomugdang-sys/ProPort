import 'package:flutter/material.dart';

import '../../../constants/app_text_styles.dart';
import '../../../services/api_client.dart';
import '../../../services/document_scope.dart';
import '../../../services/document_service.dart';
import '../../../services/portfolio_scope.dart';
import '../../../services/portfolio_template.dart';
import '../../../widgets/app_skeleton.dart';

/// Reuses authenticated document state; a failed load is never a zero count.
class PortfolioDocumentsBuilder extends StatefulWidget {
  const PortfolioDocumentsBuilder({
    super.key,
    required this.builder,
    this.overrides,
  });

  final Widget Function(DocumentService documents, PortfolioTemplate template)
  builder;
  final PortfolioTemplateOverride? overrides;

  @override
  State<PortfolioDocumentsBuilder> createState() =>
      _PortfolioDocumentsBuilderState();
}

class _PortfolioDocumentsBuilderState extends State<PortfolioDocumentsBuilder> {
  bool _requested = false;
  bool _waiting = true;
  String? _error;
  PortfolioTemplate? _template;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _waiting = true;
      _error = null;
    });
    try {
      final portfolios = PortfolioScope.maybeOf(context);
      if (portfolios == null) throw const FormatException();
      _template = await portfolios.loadTemplate(force: true);
      if (!mounted) return;
      await DocumentScope.of(context).load(force: true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is ApiException
              ? (error.message.isNotEmpty
                    ? error.message
                    : 'Unable to load portfolio documents. Please try again.')
              : 'Unable to load portfolio documents. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _waiting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = DocumentScope.of(context);
    if (_waiting || service.isLoading) {
      return const Padding(
        key: Key('portfolio-documents-loading'),
        padding: EdgeInsets.all(24),
        child: PortfolioPreviewSkeleton(),
      );
    }
    final error = _error ?? service.errorMessage;
    if (error != null ||
        _template == null ||
        !service.hasLoadedDocuments ||
        !service.hasLoadedCategories) {
      return Column(
        key: const Key('portfolio-documents-error'),
        children: [
          Text(
            error ?? 'Documents are not available. Please try again.',
            style: AppTextStyles.bodySmall,
          ),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      );
    }
    final effectiveTemplate = _template!.withOverrides(widget.overrides);
    return widget.builder(service, effectiveTemplate);
  }
}
