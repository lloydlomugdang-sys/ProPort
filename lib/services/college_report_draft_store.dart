import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-local drafts are separate from acknowledged, exportable responses.
abstract class CollegeReportDraftStore {
  Future<String?> read(String owner);
  Future<void> write(String owner, String? value);
}

class SecureCollegeReportDraftStore implements CollegeReportDraftStore {
  const SecureCollegeReportDraftStore();
  static const _storage = FlutterSecureStorage();
  String _key(String owner) => 'college_report_draft_v2_$owner';

  @override
  Future<String?> read(String owner) => _storage.read(key: _key(owner));

  @override
  Future<void> write(String owner, String? value) => value == null
      ? _storage.delete(key: _key(owner))
      : _storage.write(key: _key(owner), value: value);
}
