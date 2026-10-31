import 'document_models.dart';

/// Read-only institutional structure returned by the authenticated backend.
/// No independent Flutter section-order defaults and no student mutations.
class PortfolioTemplate {
  const PortfolioTemplate({
    required this.id,
    required this.name,
    required this.version,
    required this.includeTableOfContents,
    required this.sections,
  });

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

  PortfolioTemplate withOverrides(PortfolioTemplateOverride? overrides) {
    if (overrides == null) return this;
    final overrideMap = {for (final o in overrides.sections) o.key: o};
    final mergedSections = sections.map((rule) {
      final o = overrideMap[rule.key];
      if (o == null) return rule;
      return PortfolioTemplateSection(
        key: rule.key,
        label: o.label ?? rule.label,
        order: o.order ?? rule.order,
        enabled: o.enabled ?? rule.enabled,
        required: rule.required,
        generateCreativeTitle: o.generateCreativeTitle ?? rule.generateCreativeTitle,
      );
    }).toList()..sort((a, b) => a.order.compareTo(b.order));

    return PortfolioTemplate(
      id: id,
      name: name,
      version: version,
      includeTableOfContents: overrides.includeTableOfContents ?? includeTableOfContents,
      sections: List.unmodifiable(mergedSections),
    );
  }
}

class PortfolioTemplateSection {
  const PortfolioTemplateSection({
    required this.key,
    required this.label,
    required this.order,
    required this.enabled,
    required this.required,
    required this.generateCreativeTitle,
  });

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

  PortfolioTemplateSection copyWith({
    String? label,
    int? order,
    bool? enabled,
    bool? generateCreativeTitle,
  }) => PortfolioTemplateSection(
    key: key,
    label: label ?? this.label,
    order: order ?? this.order,
    enabled: enabled ?? this.enabled,
    required: required,
    generateCreativeTitle: generateCreativeTitle ?? this.generateCreativeTitle,
  );
}

class PortfolioSectionOverride {
  const PortfolioSectionOverride({
    required this.key,
    this.label,
    this.order,
    this.enabled,
    this.generateCreativeTitle,
  });

  final String key;
  final String? label;
  final int? order;
  final bool? enabled;
  final bool? generateCreativeTitle;

  factory PortfolioSectionOverride.fromJson(Map<String, dynamic> json) {
    return PortfolioSectionOverride(
      key: json['key'] as String,
      label: json['label'] as String?,
      order: json['order'] as int?,
      enabled: json['enabled'] as bool?,
      generateCreativeTitle: json['generateCreativeTitle'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    if (label != null) 'label': label,
    if (order != null) 'order': order,
    if (enabled != null) 'enabled': enabled,
    if (generateCreativeTitle != null) 'generateCreativeTitle': generateCreativeTitle,
  };
}

class PortfolioTemplateOverride {
  const PortfolioTemplateOverride({
    this.includeTableOfContents,
    this.sections = const [],
  });

  final bool? includeTableOfContents;
  final List<PortfolioSectionOverride> sections;

  factory PortfolioTemplateOverride.fromJson(Map<String, dynamic> json) {
    return PortfolioTemplateOverride(
      includeTableOfContents: json['includeTableOfContents'] as bool?,
      sections: (json['sections'] as List? ?? const [])
          .map((s) => PortfolioSectionOverride.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (includeTableOfContents != null) 'includeTableOfContents': includeTableOfContents,
    if (sections.isNotEmpty) 'sections': sections.map((s) => s.toJson()).toList(),
  };

  bool get isEmpty => includeTableOfContents == null && sections.isEmpty;
}
