import '../../../services/document_models.dart';
import '../../../services/portfolio_template.dart';

/// Presentation ordering only; the server exports the complete owner collection.
/// Category/folder identities and documents are never changed here.
abstract final class PortfolioDocumentOrder {
  static String sectionFor(
    DocumentRecord document,
    PortfolioTemplate template,
  ) {
    final category = document.categoryKey == 'cv'
        ? 'curriculum-vitae'
        : document.categoryKey;
    return template.section(category)?.label ?? category;
  }

  static String label(String section) => section;

  static List<DocumentRecord> sorted(
    List<DocumentRecord> documents,
    List<DocumentCategory> categories,
    PortfolioTemplate template,
  ) {
    final sections = [...template.enabledSections.map((s) => s.key)];
    int sectionRank(DocumentRecord document) {
      final index = sections.indexOf(PortfolioTemplate.keyFor(document));
      return index < 0 ? sections.length : index;
    }

    int folderRank(DocumentRecord document) {
      if (document.folderKey == 'creative-title') return -1;
      // Category API already returns folders in seeded sortOrder.
      final categoryKey = document.categoryKey == 'cv'
          ? 'curriculum-vitae'
          : document.categoryKey;
      final folders = categories
          .where((category) => category.key == categoryKey)
          .firstOrNull
          ?.folders;
      final index =
          folders?.indexWhere((f) => f.key == document.folderKey) ?? -1;
      return index < 0 ? 1000000 : index;
    }

    return documents.where(template.includes).toList()..sort((a, b) {
      var result = sectionRank(a).compareTo(sectionRank(b));
      if (result != 0) return result;
      result = folderRank(a).compareTo(folderRank(b));
      if (result != 0) return result;
      result = a.folderKey.compareTo(b.folderKey);
      if (result != 0) return result;
      result = a.documentDate.compareTo(b.documentDate);
      if (result != 0) return result;
      result = a.createdAt.compareTo(b.createdAt);
      return result == 0 ? a.id.compareTo(b.id) : result;
    });
  }
}
