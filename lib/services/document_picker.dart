import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'package:image_picker/image_picker.dart';

import 'document_models.dart';

abstract class DocumentPicker {
  Future<PickedDocument?> pickDocument();

  Future<List<PickedDocument>?> pickDocuments({
    bool allowMultiple = true,
  }) async {
    final single = await pickDocument();
    return single == null ? null : [single];
  }

  Future<PickedDocument?> pickFromCamera() async => null;
}

class DeviceDocumentPicker implements DocumentPicker {
  DeviceDocumentPicker({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  @override
  Future<PickedDocument?> pickDocument() async {
    final docs = await pickDocuments(allowMultiple: false);
    return docs?.firstOrNull;
  }

  @override
  Future<PickedDocument?> pickFromCamera() async {
    final photo = await _imagePicker.pickImage(
      source: ImageSource.camera,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );
    if (photo == null) return null;

    final bytes = await photo.readAsBytes();
    final ext = photo.name.contains('.')
        ? photo.name.split('.').last.toLowerCase()
        : 'jpg';
    final name = photo.name.isNotEmpty
        ? photo.name
        : 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return PickedDocument(
      name: name,
      mimeType: _mimeTypeFor(ext),
      bytes: bytes,
    );
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
