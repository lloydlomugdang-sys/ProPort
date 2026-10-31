import 'package:flutter/material.dart';
import '../../../services/api_client.dart';
import '../../../services/portfolio_scope.dart';
import '../../../services/portfolio_template.dart';
import '../models/portfolio_models.dart';

/// Optional student-authored text only. Institutional template rules are read-only.
class PortfolioCreativeTitlesDialog extends StatefulWidget {
  const PortfolioCreativeTitlesDialog({
    super.key,
    required this.portfolio,
    required this.template,
  });
  final PortfolioRecord portfolio;
  final PortfolioTemplate template;
  @override
  State<PortfolioCreativeTitlesDialog> createState() =>
      _PortfolioCreativeTitlesDialogState();
}

class _PortfolioCreativeTitlesDialogState
    extends State<PortfolioCreativeTitlesDialog> {
  late final _controllers = {
    for (final rule in widget.template.enabledSections.where(
      (s) => s.generateCreativeTitle,
    ))
      rule.key: TextEditingController(
        text: widget.portfolio.info.creativeTitles[rule.key] ?? '',
      ),
  };
  bool _saving = false;
  String? _error;
  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final titles = Map<String, String>.of(
        widget.portfolio.info.creativeTitles,
      );
      for (final entry in _controllers.entries) {
        titles[entry.key] = entry.value.text.trim();
      }
      final saved = await PortfolioScope.of(
        context,
      ).saveCreativeTitles(widget.portfolio.id, titles);
      if (mounted) Navigator.pop(context, saved);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException
              ? error.message
              : 'Unable to save Creative Titles. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Section Creative Titles'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Optional. One saved title becomes one page before that section. Leave blank to keep an existing uploaded Creative Title. Do not use both.',
            ),
            for (final rule in widget.template.enabledSections.where(
              (s) => s.generateCreativeTitle,
            ))
              TextField(
                key: ValueKey('creative-title-${rule.key}'),
                controller: _controllers[rule.key],
                maxLength: 200,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: rule.label,
                  alignLabelWithHint: true,
                ),
                maxLines: 2,
              ),
            if (_error != null)
              Text(_error!, key: const Key('creative-titles-error')),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Save Creative Titles'),
        ),
      ],
    ),
  );
}
