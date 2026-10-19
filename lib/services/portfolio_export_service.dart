import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../screens/portfolio/models/portfolio_models.dart';
import '../screens/portfolio/models/portfolio_document_order.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'document_service.dart';

typedef FileSaveFunction =
    Future<String?> Function({
      String? dialogTitle,
      String? fileName,
      String? initialDirectory,
      FileType type,
      List<String>? allowedExtensions,
      Uint8List? bytes,
      bool lockParentWindow,
    });

/// An explicit public-data projection: no tokens, storage keys or internal IDs.
class PortfolioExportContent {
  const PortfolioExportContent({
    required this.titleFields,
    required this.sections,
    required this.totalDocuments,
  });

  final Map<String, String> titleFields;
  final List<PortfolioExportSection> sections;
  final int totalDocuments;
  int get includedDocuments =>
      sections.fold(0, (sum, section) => sum + section.documents.length);

  String get coverageNote => includedDocuments < totalDocuments
      ? 'Includes $includedDocuments of $totalDocuments stored documents. '
            'The current document API returns at most 100 entries; this export is incomplete.'
      : 'Includes $includedDocuments stored documents.';

  factory PortfolioExportContent.fromDocuments(
    PortfolioInfo info,
    DocumentService service,
  ) {
    if (info.validationErrors.isNotEmpty) {
      throw PortfolioExportException(
        'Please edit the portfolio title page. ${info.validationErrors.values.first}',
      );
    }
    if (service.isLoading ||
        !service.hasLoadedDocuments ||
        !service.hasLoadedCategories ||
        service.errorMessage != null) {
      throw const PortfolioExportException(
        'Documents are not ready. Please try exporting again.',
      );
    }
    final summary = PortfolioSummary.fromDocumentSummary(service.summary);
    final groups = <String, List<Map<String, String>>>{
      for (final section in summary.sections)
        if (section.name != 'Creative Title') section.name: [],
    };
    for (final document in PortfolioDocumentOrder.sorted(
      service.documents,
      service.categories,
    )) {
      final category = service.categories
          .where((value) => value.key == document.categoryKey)
          .firstOrNull;
      final folder = category?.folders
          .where((value) => value.key == document.folderKey)
          .firstOrNull;
      final section = PortfolioDocumentOrder.sectionFor(document);
      groups.putIfAbsent(section, () => []).add({
        'Title': document.title,
        'Date': document.documentDate.toIso8601String().substring(0, 10),
        'Category': category?.name ?? section,
        'Folder': folder?.name ?? document.folderKey,
        'File': document.originalFileName,
        if ((document.descriptionSource == 'user' || document.descriptionSource == 'confirmed') &&
            (document.description?.trim().isNotEmpty ?? false))
          'Description': document.description!,
        if (document.reflection?.trim().isNotEmpty ?? false)
          'Reflection': document.reflection!,
      });
    }
    return PortfolioExportContent(
      titleFields: {
        'Full Name': info.fullName,
        'Year & Section': info.yearAndSection,
        'Schedule': info.formattedSchedule,
        "Instructor's Name": info.instructorName,
        'Course': info.course,
        'Course Code': info.courseCode,
        'Semester & Academic Year': info.semesterAndYear,
      },
      sections: [
        for (final entry in groups.entries)
          PortfolioExportSection(entry.key, entry.value),
      ],
      totalDocuments: service.summary.totalCount,
    );
  }
}

class PortfolioExportSection {
  const PortfolioExportSection(this.name, this.documents);

  final String name;
  final List<Map<String, String>> documents;
}

class PortfolioExportException implements Exception {
  const PortfolioExportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PortfolioExportFile {
  const PortfolioExportFile({
    required this.path,
    required this.name,
    required this.format,
    required this.sizeBytes,
  });

  final String path;
  final String name;
  final ExportFormat format;
  final int sizeBytes;
  String get mimeType => format == ExportFormat.pdf
      ? 'application/pdf'
      : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
}

/// Injected through PortfolioScope for tests; it owns no account/document state.
abstract interface class PortfolioExporter {
  Future<PortfolioExportFile> generate(
    PortfolioExportContent content,
    ExportFormat format,
  );
  Future<void> share(PortfolioExportFile file, Rect origin);
  Future<bool> saveToDevice(PortfolioExportFile file);
}

class DevicePortfolioExporter implements PortfolioExporter {
  const DevicePortfolioExporter({
    this.store,
    this.authService,
    this.fileSaveFunction,
  });

  final PortfolioExportStore? store;
  final AuthService? authService;
  final FileSaveFunction? fileSaveFunction;

  @override
  Future<PortfolioExportFile> generate(
    PortfolioExportContent content,
    ExportFormat format,
  ) async {
    final Uint8List bytes;
    final titleInfo = PortfolioInfo(
      fullName: content.titleFields['Full Name'] ?? '',
      yearAndSection: content.titleFields['Year & Section'] ?? '',
      schedule: content.titleFields['Schedule'] ?? '',
      instructorName: content.titleFields["Instructor's Name"] ?? '',
      course: content.titleFields['Course'] ?? '',
      courseCode: content.titleFields['Course Code'] ?? '',
      semesterAndYear: content.titleFields['Semester & Academic Year'] ?? '',
    );
    if (titleInfo.validationErrors.isNotEmpty) {
      throw PortfolioExportException(
        'Please edit the portfolio title page. ${titleInfo.validationErrors.values.first}',
      );
    }
    if (authService == null) {
      throw const PortfolioExportException(
        'Unable to generate your complete portfolio. Check your connection and try again.',
      );
    }
    try {
      bytes = await authService!.authenticatedPostBytes(
        '/api/v1/portfolios/export/${format.name}',
        body: titleInfo.normalizedMap,
        requestTimeout: const Duration(seconds: 90),
      );
    } on ApiException catch (error) {
      if (error.code == 'NETWORK_TIMEOUT' || error.code == 'COLD_START_TIMEOUT') {
        throw const PortfolioExportException(
          'Portfolio generation took too long. Keep the app connected and retry. If it happens again, export fewer or smaller source files.',
        );
      }
      if (error.statusCode == 0 ||
          error.code == 'NETWORK_ERROR' ||
          error.message.contains('reach the server') ||
          error.message.contains('connection')) {
        throw const PortfolioExportException(
          'Unable to generate your complete portfolio. Check your connection and try again.',
        );
      }
      throw PortfolioExportException(error.message);
    } catch (_) {
      throw const PortfolioExportException(
        'Unable to generate your complete portfolio. Check your connection and try again.',
      );
    }
    return (store ?? PortfolioExportStore()).write(
      bytes,
      portfolioFileName(content.titleFields['Full Name'] ?? '', format),
      format,
    );
  }

  @override
  Future<void> share(PortfolioExportFile file, Rect origin) async {
    if (!await File(file.path).exists()) {
      throw const PortfolioExportException(
        'The temporary file is no longer available. Please export again.',
      );
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: file.mimeType)],
        subject: 'GradPort Portfolio',
        sharePositionOrigin: origin,
      ),
    );
    // A dismissed share sheet is not a failed generation or a claimed save.
  }

  @override
  Future<bool> saveToDevice(PortfolioExportFile file) async {
    final localFile = File(file.path);
    if (!await localFile.exists()) {
      throw const PortfolioExportException(
        'The temporary file is no longer available. Please export again.',
      );
    }
    final bytes = await localFile.readAsBytes();
    final save = fileSaveFunction ?? FilePicker.saveFile;
    final result = await save(
      dialogTitle: 'Save Portfolio',
      fileName: file.name,
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: [file.format.name],
    );
    return result != null;
  }
}

String portfolioFileName(String fullName, ExportFormat format) {
  var student = fullName
      .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (student.isEmpty) student = 'Student';
  if (student.length > 60) student = student.substring(0, 60);
  return 'GradPort_${student}_Portfolio.${format.name}';
}

/// Writes only to unique app-cache subdirectories; never shared external storage.
class PortfolioExportStore {
  PortfolioExportStore({Future<Directory> Function()? temporaryDirectory})
    : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final Future<Directory> Function() _temporaryDirectory;

  Future<PortfolioExportFile> write(
    Uint8List bytes,
    String name,
    ExportFormat format,
  ) async {
    if (bytes.isEmpty ||
        !RegExp(
          r'^GradPort_[A-Za-z0-9_-]+_Portfolio\.(pdf|docx)$',
        ).hasMatch(name)) {
      throw const PortfolioExportException('Unable to create the export file.');
    }
    final temporary = await _temporaryDirectory();
    final root = await Directory(
      '${temporary.path}/gradport_exports',
    ).create(recursive: true);
    final directory = await root.createTemp('export_');
    final file = File('${directory.path}/$name');
    try {
      await file.writeAsBytes(bytes, flush: true);
      if (await file.length() != bytes.length) {
        throw const PortfolioExportException(
          'Unable to finish writing the file.',
        );
      }
      return PortfolioExportFile(
        path: file.path,
        name: name,
        format: format,
        sizeBytes: bytes.length,
      );
    } catch (_) {
      // Only the exact file/directory created above is eligible for cleanup.
      if (await file.exists()) await file.delete();
      await directory.delete();
      rethrow;
    }
  }
}

String portfolioExportError(Object error) {
  if (error is ApiException) {
    if (error.statusCode == 429 || error.code == 'RATE_LIMITED') {
      return 'Too many export attempts. Please wait a moment and try again.';
    }
    if (error.statusCode != null && error.statusCode! >= 500) {
      return 'The export server is temporarily unavailable. Please try again.';
    }
    if (error.code == 'NETWORK_ERROR') {
      return 'Unable to connect. Check your internet connection and try again.';
    }
    if (error.code == 'NETWORK_TIMEOUT') {
      return 'The export took too long to respond. Please try again.';
    }
    if (error.statusCode == 401) {
      return 'Your session has expired. Please log in again.';
    }
    return error.message.isNotEmpty
        ? error.message
        : 'Unable to export the portfolio. Please try again.';
  }
  if (error is PortfolioExportException) return error.message;
  return 'Unable to export the portfolio. Please try again.';
}
