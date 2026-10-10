// LOCATION: lib/services/document_picker.dart
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../screens/files/document_scan_review_screen.dart';
import 'document_models.dart';
import 'scanner/classical_cv_engine.dart';

/// Delegate for handling the document review screen or mocking scan execution in tests.
typedef DocumentScannerRunner =
    Future<String?> Function({
      required String imagePath,
      required DocumentCorners initialCorners,
    });

/// Delegate for cleaning temporary scanner cache files.
typedef DocumentScannerCleaner = Future<void> Function();

/// Delegate for picking camera photos (allowing mock injection in tests).
typedef CameraPhotoPicker =
    Future<XFile?> Function({
      required ImageSource source,
      double? maxWidth,
      double? maxHeight,
      int? imageQuality,
    });

Future<void> _defaultScannerCleaner() async {
  try {
    final tempDir = await getTemporaryDirectory();
    final files = tempDir.listSync();
    for (final entity in files) {
      if (entity is File) {
        final name = entity.uri.pathSegments.last;
        if (name.startsWith('scan_') && name.endsWith('.jpg')) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    }
  } catch (_) {
    // Ignore cache cleanup failures so core app flows are never blocked.
  }
}

abstract class DocumentPicker {
  Future<PickedDocument?> pickDocument();

  Future<List<PickedDocument>?> pickDocuments({
    bool allowMultiple = true,
  }) async {
    final single = await pickDocument();
    return single == null ? null : [single];
  }

  Future<PickedDocument?> pickFromCamera() async => null;

  Future<void> cleanCache() async {}
}

class DeviceDocumentPicker implements DocumentPicker {
  DeviceDocumentPicker({
    ImagePicker? imagePicker,
    CameraPhotoPicker? photoPicker,
    DocumentScannerRunner? scannerRunner,
    DocumentScannerCleaner? scannerCleaner,
  }) : _imagePicker = imagePicker ?? ImagePicker(),
       _photoPicker = photoPicker,
       _scannerRunner = scannerRunner,
       _scannerCleaner = scannerCleaner ?? _defaultScannerCleaner;

  /// Global navigator key allowing the scanner review screen to be pushed from camera entry points.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  final ImagePicker _imagePicker;
  final CameraPhotoPicker? _photoPicker;
  final DocumentScannerRunner? _scannerRunner;
  final DocumentScannerCleaner _scannerCleaner;

  @override
  Future<PickedDocument?> pickDocument() async {
    final docs = await pickDocuments(allowMultiple: false);
    return docs?.firstOrNull;
  }

  @override
  Future<PickedDocument?> pickFromCamera() async {
    final XFile? photo;
    try {
      if (_photoPicker != null) {
        photo = await _photoPicker(
          source: ImageSource.camera,
          maxWidth: 2400,
          maxHeight: 2400,
          imageQuality: 92,
        );
      } else {
        photo = await _imagePicker.pickImage(
          source: ImageSource.camera,
          maxWidth: 2400,
          maxHeight: 2400,
          imageQuality: 92,
        );
      }
    } catch (e) {
      throw FileSystemException(
        'Unable to complete document scan: ${e.toString()}',
      );
    }

    if (photo == null) return null;

    final photoPath = photo.path;
    final photoFile = File(photoPath);
    if (!await photoFile.exists()) {
      throw const FileSystemException(
        'The scanned document could not be found.',
      );
    }

    final size = await photoFile.length();
    if (size == 0) {
      throw const FileSystemException('The scanned document is empty.');
    }

    final rawBytes = await photoFile.readAsBytes();
    final corners = await ClassicalCvEngine.detectCornersAsync(rawBytes);

    final String? processedPath;
    if (_scannerRunner != null) {
      processedPath = await _scannerRunner(
        imagePath: photoPath,
        initialCorners: corners,
      );
    } else if (navigatorKey.currentState != null) {
      processedPath = await navigatorKey.currentState!.push<String>(
        MaterialPageRoute(
          builder: (_) => DocumentScanReviewScreen(
            imagePath: photoPath,
            initialCorners: corners,
          ),
        ),
      );
    } else {
      // Headless / non-navigated fallback: warp using detected corners directly
      final processedBytes = await ClassicalCvEngine.warpAndEnhanceAsync(
        WarpParams(
          imageBytes: rawBytes,
          corners: corners,
          // A failed detection must not apply an arbitrary inset or destructive
          // enhancement. Keep the full normalized capture in headless flows.
          mode: corners.isAutoDetected
              ? ScanEnhancementMode.enhanced
              : ScanEnhancementMode.original,
        ),
      );
      final tempDir = await getTemporaryDirectory();
      final outName = 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final outFile = File('${tempDir.path}/$outName');
      await outFile.writeAsBytes(processedBytes);
      processedPath = outFile.path;
    }

    if (processedPath == null) return null;

    final processedFile = File(processedPath);
    if (!await processedFile.exists()) {
      throw const FileSystemException(
        'The scanned document could not be found.',
      );
    }

    final sizeBytes = await processedFile.length();
    if (sizeBytes == 0) {
      throw const FileSystemException('The scanned document is empty.');
    }

    final name = 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';

    return PickedDocument(
      name: name,
      mimeType: 'image/jpeg',
      path: processedPath,
      sizeBytes: sizeBytes,
    );
  }

  @override
  Future<void> cleanCache() async {
    try {
      await _scannerCleaner();
    } catch (_) {
      // Ignore cache cleanup failures so core app flows are never blocked.
    }
  }

  @override
  Future<List<PickedDocument>?> pickDocuments({
    bool allowMultiple = true,
  }) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: allowMultiple,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final pickedList = <PickedDocument>[];
    for (final selected in result.files) {
      final path = selected.path;
      final bytes = selected.bytes;
      if ((path == null || path.isEmpty) && bytes == null) {
        throw const FileSystemException('The selected file could not be read.');
      }
      pickedList.add(
        PickedDocument(
          name: selected.name,
          mimeType: _mimeTypeFor(selected.extension),
          path: path,
          sizeBytes: selected.size,
          bytes: bytes,
        ),
      );
    }
    return pickedList;
  }

  static String _mimeTypeFor(String? extension) {
    return switch (extension?.toLowerCase()) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      _ => 'application/octet-stream',
    };
  }
}
