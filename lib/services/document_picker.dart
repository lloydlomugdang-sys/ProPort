import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'document_models.dart';

abstract interface class DocumentPicker {
  Future<PickedDocument?> pickDocument();
}

class DeviceDocumentPicker implements DocumentPicker {
  @override
  Future<PickedDocument?> pickDocument() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final selected = result.files.single;
    final bytes =
        selected.bytes ??
        (selected.path == null
            ? null
            : await File(selected.path!).readAsBytes());
    if (bytes == null) {
      throw const FileSystemException('The selected file could not be read.');
    }
    return PickedDocument(
      name: selected.name,
      mimeType: _mimeTypeFor(selected.extension),
      bytes: bytes,
    );
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
