import 'dart:async';

import 'package:flutter/services.dart';
import 'package:proport_app/screens/portfolio/models/portfolio_models.dart';
import 'package:proport_app/services/portfolio_export_service.dart';

/// Real file encoding; only OS storage and sharing are replaced in widget tests.
class MemoryPortfolioExporter implements PortfolioExporter {
  int generationCount = 0;
  int shareCount = 0;
  Uint8List? bytes;
  ExportFormat? format;
  PortfolioExportContent? content;
  Completer<void>? pending;
  bool fail = false;
  bool failShare = false;

  @override
  Future<PortfolioExportFile> generate(
    PortfolioExportContent content,
    ExportFormat format,
  ) async {
    generationCount++;
    this.content = content;
    this.format = format;
    if (pending != null) await pending!.future;
    if (fail) {
      throw StateError('private filesystem detail must not be displayed');
    }
    bytes = format == ExportFormat.pdf
        ? await PortfolioFileRenderer.pdf(
            content,
            await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
            await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
          )
        : PortfolioFileRenderer.docx(content);
    final name = portfolioFileName(content.titleFields['Full Name']!, format);
    return PortfolioExportFile(
      path: '/test-only/$name',
      name: name,
      format: format,
      sizeBytes: bytes!.length,
    );
  }

  @override
  Future<void> share(PortfolioExportFile file, Rect origin) async {
    shareCount++;
    if (failShare) throw StateError('private platform detail');
  }
}
