import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../constants/app_colors.dart';
import '../../services/api_client.dart';
import '../../services/document_models.dart';
import '../../services/document_scope.dart';
import '../../widgets/grad_app_bar.dart';
import 'document_ocr_screen.dart';

/// Visual source viewing only. No extraction or classification is requested.
class DocumentPdfScreen extends StatefulWidget {
  const DocumentPdfScreen({super.key, required this.document});

  final DocumentRecord document;

  @override
  State<DocumentPdfScreen> createState() => _DocumentPdfScreenState();
}

class _DocumentPdfScreenState extends State<DocumentPdfScreen> {
  late final _files = [...widget.document.effectiveAttachments]
    ..sort((a, b) => a.order.compareTo(b.order));
  int _fileIndex = 0;
  int _attempt = 0;
  Future<Uint8List>? _content;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _content ??= _fetch();
  }

  Future<Uint8List> _fetch() => DocumentScope.of(context).getDocumentContent(
    widget.document.id,
    attachmentId: _fileIndex == 0 ? null : _files[_fileIndex].id,
  );

  void _reload([int? fileIndex]) => setState(() {
    _fileIndex = fileIndex ?? _fileIndex;
    _attempt++;
    _content = _fetch();
  });

  Widget _failure(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          TextButton(onPressed: _reload, child: const Text('Retry')),
        ],
      ),
    ),
  );

  String _fetchError(Object? error) {
    if (error is ApiException) {
      if (error.statusCode == 404) {
        return 'The source file is no longer available. Please check your uploaded files.';
      }
      if (error.statusCode == 401 || error.statusCode == 403) {
        return 'Your session could not be verified. Please sign in again.';
      }
    }
    return 'Unable to load the source file. Please retry when connected.';
  }

  @override
  Widget build(BuildContext context) {
    final file = _files[_fileIndex];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const GradBackAppBar(title: 'Document Preview'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(file.originalFileName, textAlign: TextAlign.center),
          ),
          if (_files.length > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Previous file',
                  onPressed: _fileIndex > 0
                      ? () => _reload(_fileIndex - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('File ${_fileIndex + 1} of ${_files.length}'),
                IconButton(
                  tooltip: 'Next file',
                  onPressed: _fileIndex + 1 < _files.length
                      ? () => _reload(_fileIndex + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          Expanded(
            child: FutureBuilder<Uint8List>(
              future: _content,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _failure(_fetchError(snapshot.error));
                }
                final bytes = snapshot.data;
                if (bytes == null || bytes.isEmpty) {
                  return _failure('The source file is empty or unavailable.');
                }
                if (file.fileKind != 'pdf') {
                  return InteractiveViewer(
                    maxScale: 4,
                    child: Center(
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => _failure(
                          'This source image could not be displayed.',
                        ),
                      ),
                    ),
                  );
                }
                return PdfPreview.builder(
                  key: ValueKey('source-pdf-$_fileIndex-$_attempt'),
                  // Original bytes, never an OCR reconstruction. A null pages
                  // filter renders every source page, not the attachment count.
                  build: (_) => bytes,
                  dpi: 72,
                  useActions: false,
                  allowPrinting: false,
                  allowSharing: false,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  onError: (_, _) => _failure(
                    'This PDF could not be displayed. Please retry or upload a readable copy.',
                  ),
                  pagesBuilder: (context, pages) => ListView.builder(
                    itemCount: pages.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Text('Page ${index + 1} of ${pages.length}'),
                          const SizedBox(height: 8),
                          InteractiveViewer(
                            maxScale: 4,
                            child: Image(
                              image: pages[index].image,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: TextButton.icon(
              icon: const Icon(Icons.text_snippet_outlined),
              label: const Text('Review extracted text'),
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => DocumentOcrScreen(document: widget.document),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
