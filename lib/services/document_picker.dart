import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'document_models.dart';

abstract class DocumentPicker {
  Future<PickedDocument?> pickDocument();

  Future<List<PickedDocument>?> pickDocuments({
    bool allowMultiple = true,
  }) async {
    final single = await pickDocument();
    return single == null ? null : [single];
  }
}

class DeviceDocumentPicker implements DocumentPicker {
  @override
  Future<PickedDocument?> pickDocument() async {
    final docs = await pickDocuments(allowMultiple: false);
    return docs?.firstOrNull;
  }

  @override
  Future<List<PickedDocument>?> pickDocuments({
    bool allowMultiple = true,
  }) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: allowMultiple,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final pickedList = <PickedDocument>[];
    for (final selected in result.files) {
      final bytes =
          selected.bytes ??
          (selected.path == null
              ? null
              : await File(selected.path!).readAsBytes());
      if (bytes == null) {
        throw const FileSystemException('The selected file could not be read.');
      }
      pickedList.add(
        PickedDocument(
          name: selected.name,
          mimeType: _mimeTypeFor(selected.extension),
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
