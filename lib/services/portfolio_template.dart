import 'document_models.dart';

/// Read-only institutional structure returned by the authenticated backend.
/// No independent Flutter section-order defaults and no student mutations.
class PortfolioTemplate {
  PortfolioTemplate.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String,
      version = json['version'] as int,
      includeTableOfContents = json['includeTableOfContents'] as bool,
      sections = List.unmodifiable(
        (json['sections'] as List)
            .map(
              (s) =>
                  PortfolioTemplateSection.fromJson(s as Map<String, dynamic>),
            )
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order)),
      ) {
    if (json['status'] != 'active' ||
        version < 1 ||
        sections.map((s) => s.key).toSet().length != sections.length ||
        sections.map((s) => s.order).toSet().length != sections.length) {
      throw const FormatException('Invalid portfolio template');
    }
  }
  final String id;
  final String name;
  final int version;
  final bool includeTableOfContents;
  final List<PortfolioTemplateSection> sections;
  Iterable<PortfolioTemplateSection> get enabledSections =>
      sections.where((s) => s.enabled);
  PortfolioTemplateSection? section(String key) =>
      sections.where((s) => s.key == key).firstOrNull;
  static String keyFor(DocumentRecord document) =>
      document.categoryKey == 'cv' ? 'curriculum-vitae' : document.categoryKey;
  bool includes(DocumentRecord document) {
    final rule = section(keyFor(document));
    return rule != null &&
        rule.enabled &&
        (document.folderKey != 'creative-title' || rule.generateCreativeTitle);
  }
}

class PortfolioTemplateSection {
  PortfolioTemplateSection.fromJson(Map<String, dynamic> json)
    : key = json['key'] as String,
      label = json['label'] as String,
      order = json['order'] as int,
      enabled = json['enabled'] as bool,
      required = json['required'] as bool,
      generateCreativeTitle = json['generateCreativeTitle'] as bool;
  final String key;
  final String label;
  final int order;
  final bool enabled;
  final bool required;
  final bool generateCreativeTitle;
}
