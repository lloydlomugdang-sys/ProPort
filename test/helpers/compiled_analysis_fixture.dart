import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/document_models.dart';

/// Feed existing metadata UI scenarios through the page-analysis response.
CompiledAnalysisResult singlePdfAnalysis(
  PickedDocument file,
  DocumentOcrResult ocr,
) {
  if (!ocr.isReady) {
    throw const ApiException(
      code: 'OCR_FAILED',
      message: 'Automatic reading failed.',
    );
  }
  final suggestions = ocr.metadataSuggestions;
  return CompiledAnalysisResult(
    sessionId: 'test_${file.name}',
    originalFileName: file.name,
    totalPages: 1,
    detection: 'single',
    pages: [
      CompiledPageResult(
        pageNumber: 1,
        text: ocr.rawText ?? '',
        source: 'digital',
        status: 'ready',
      ),
    ],
    documents: [
      CompiledDocumentProposal(
        startPage: 1,
        endPage: 1,
        categoryKey: suggestions?.categoryKey ?? '',
        folderKey: suggestions?.folderKey ?? '',
        title: suggestions?.title ?? '',
        documentDate: suggestions?.documentDate,
      ),
    ],
    metadataSuggestions: suggestions ?? const DocumentMetadataSuggestions(),
    metadataAnalysis: ocr.metadataAnalysis,
  );
}
