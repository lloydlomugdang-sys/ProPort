// LOCATION: lib/screens/files/models/added_file_model.dart
//
// Temporary in-memory storage only.
// Replace AddedFileStore with a real MongoDB / API service later.

import 'package:flutter/foundation.dart';

/// Represents a single document added by the user.
/// Structure mirrors what will eventually be stored in MongoDB.
class AddedFile {
  AddedFile({
    required this.id,
    required this.fileName,
    required this.contentType,
    required this.folder,
    required this.title,
    required this.date,
    this.description,
    this.reflection,
    this.filePath,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String fileName;
  final String contentType;
  final String folder;
  final String title;
  final DateTime date;
  final String? description;
  final String? reflection;
  final String? filePath; // local path for now; becomes a URL later
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
        'id':          id,
        'fileName':    fileName,
        'contentType': contentType,
        'folder':      folder,
        'title':       title,
        'date':        date.toIso8601String(),
        'description': description,
        'reflection':  reflection,
        'filePath':    filePath,
        'createdAt':   createdAt.toIso8601String(),
      };
}

/// In-memory file store.
/// Replace [addFile] / [removeFile] with real MongoDB calls when backend
/// is ready — the rest of the app only calls these two methods.
class AddedFileStore extends ChangeNotifier {
  final List<AddedFile> _files = [];

  List<AddedFile> get files => List.unmodifiable(_files);

  int get totalCount => _files.length;

  /// TODO: Replace with MongoDB / API call.
  void addFile(AddedFile file) {
    _files.insert(0, file); // newest first
    notifyListeners();
  }

  /// TODO: Replace with MongoDB / API call.
  void removeFile(String id) {
    _files.removeWhere((f) => f.id == id);
    notifyListeners();
  }
}

/// Global singleton store.
final addedFileStore = AddedFileStore();

// ─── Content type and folder options ─────────────────────────────────────────
// These lists match the GradPort category structure from the Files module.
// Update them when the backend provides dynamic values.

const List<String> kContentTypes = [
  'Curriculum Vitae',
  'Scholastic Record',
  'Certificates',
  'Accomplishments',
  'Other Achievements',
  'College Report',
];

const Map<String, List<String>> kFoldersByContent = {
  'Curriculum Vitae': [
    'Creative Title',
    'Curriculum Vitae',
  ],
  'Scholastic Record': [
    'Creative Title',
    'Unofficial TOR with Reflections',
  ],
  'Certificates': [
    'Creative Title',
    'Seminars',
    'Other Seminars',
    'Trainings',
  ],
  'Accomplishments': [
    'Creative Title',
    'Thesis/Capstone',
    'Case Studies',
    'Projects',
    'Assessments',
  ],
  'Other Achievements': [
    'Creative Title',
    'Projects',
  ],
  'College Report': [
    'College Report',
  ],
};