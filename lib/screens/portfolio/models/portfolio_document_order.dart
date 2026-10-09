import '../../../services/document_models.dart';
import 'portfolio_models.dart';

/// Presentation ordering only; the server exports the complete owner collection.
/// Category/folder identities and documents are never changed here.
abstract final class PortfolioDocumentOrder {
  static String sectionFor(DocumentRecord document) {
    final category = document.categoryKey == 'cv'
        ? 'curriculum-vitae'
        : document.categoryKey;
    if (!PortfolioSummary.categorySections.containsKey(category)) {
      return category;
    }
    if (document.folderKey == 'creative-title') return 'Creative Title';
    return PortfolioSummary.categorySections[category]!;
  }

  static String label(String section) => section == 'Scholastic Record'
      ? "Unofficial TOR - Bachelor's Degree with Reflection"
      : section;

  static List<DocumentRecord> sorted(
    List<DocumentRecord> documents,
    List<DocumentCategory> categories,
  ) {
    final sections = [
      'Creative Title',
      ...PortfolioSummary.categorySections.values,
    ];
    int sectionRank(DocumentRecord document) {
      final index = sections.indexOf(sectionFor(document));
      return index < 0 ? sections.length : index;
    }

    int folderRank(DocumentRecord document) {
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

    return [...documents]..sort((a, b) {
      var result = sectionRank(a).compareTo(sectionRank(b));
      if (result != 0) return result;
      // All creative titles form one front-matter group, regardless of category.
      if (sectionFor(a) != 'Creative Title') {
        result = folderRank(a).compareTo(folderRank(b));
        if (result != 0) return result;
        result = a.folderKey.compareTo(b.folderKey);
        if (result != 0) return result;
      }
      result = a.documentDate.compareTo(b.documentDate);
      if (result != 0) return result;
      result = a.createdAt.compareTo(b.createdAt);
      return result == 0 ? a.id.compareTo(b.id) : result;
    });
  }
}
