import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'college_report_models.dart';

/// Account-scoped memory draft. Only an acknowledged API save is persisted.
class CollegeReportService extends ChangeNotifier {
  CollegeReportService({required AuthService authService})
    : _auth = authService {
    _owner = _auth.user?.id;
    _auth.addListener(_authChanged);
  }

  static const _path = '/api/v1/college-report';
  final AuthService _auth;
  String? _owner;
  int _generation = 0;
  bool _disposed = false;
  CollegeReportTemplate? template;
  SavedCollegeReport? saved;
  final Map<String, Object?> _answers = {};
  Map<String, Object?> get answers => Map.unmodifiable(_answers);
  String essay = '';
  bool isLoading = false;
  bool isSaving = false;
  bool loaded = false;
  bool dirty = false;
  bool templateReady = false;
  bool hasLegacyReport = false;
  String? errorMessage;
  int draftRevision = 0;

  bool _current(int generation) => !_disposed && generation == _generation;

  Future<void> load() async {
    if (loaded || isLoading || _disposed) return;
    final generation = _generation;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _auth.authenticatedGetJson('$_path/template'),
        _auth.authenticatedGetJson('$_path/me'),
      ]);
      final parsedTemplate = CollegeReportTemplate.fromJson(
        _data(results[0])['template'] as Map<String, dynamic>,
      );
      final data = _data(results[1]);
      final report = data['report'] == null
          ? null
          : SavedCollegeReport.fromJson(data['report'] as Map<String, dynamic>);
      if (report != null && report.version != parsedTemplate.version) {
        throw const FormatException();
      }
      if (!_current(generation)) return;
      template = parsedTemplate;
      saved = report;
      templateReady = data['templateReady'] == true;
      hasLegacyReport = data['hasLegacyReport'] == true;
      _answers.addAll({
        for (final q in parsedTemplate.questions) q.key: report?.answers[q.key],
      });
      essay = report?.essay ?? '';
      loaded = true;
      draftRevision++;
    } catch (_) {
      if (_current(generation)) {
        errorMessage =
            'Unable to load your College Report. Check your connection and retry.';
      }
    } finally {
      if (_current(generation)) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  void answer(String key, Object? value) {
    if (!loaded || isSaving || !_answers.containsKey(key)) return;
    _answers[key] = value is String && value.trim().isEmpty ? null : value;
    dirty = true;
    notifyListeners();
  }

  void setEssay(String value) {
    if (!loaded || isSaving) return;
    essay = value;
    dirty = true;
    notifyListeners();
  }

  Future<bool> save() async {
    if (!loaded || isSaving || !templateReady || _disposed) return false;
    final generation = _generation;
    isSaving = true;
    errorMessage = null;
    notifyListeners();
    try {
      final response = await _auth.authenticatedPostJson(
        '$_path/me',
        body: {
          'questionnaireVersion': template!.version,
          'answers': [
            for (final entry in _answers.entries)
              {'questionKey': entry.key, 'value': entry.value},
          ],
          'essay': essay,
        },
      );
      final report = SavedCollegeReport.fromJson(
        _data(response)['report'] as Map<String, dynamic>,
      );
      if (!_current(generation)) return false;
      if (report.version != template!.version) throw const FormatException();
      saved = report;
      dirty = false;
      return true;
    } catch (_) {
      if (_current(generation)) {
        errorMessage =
            'Your changes were not saved. They are still here; check your connection and retry Save Report.';
      }
      return false;
    } finally {
      if (_current(generation)) {
        isSaving = false;
        notifyListeners();
      }
    }
  }

  static Map<String, dynamic> _data(Map<String, dynamic> envelope) =>
      envelope['data'] as Map<String, dynamic>;

  void _authChanged() {
    final owner = _auth.user?.id;
    if (owner == _owner) return;
    _owner = owner;
    _generation++;
    draftRevision++;
    template = null;
    saved = null;
    _answers.clear();
    essay = '';
    isLoading = isSaving = loaded = dirty = templateReady = hasLegacyReport =
        false;
    errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _auth.removeListener(_authChanged);
    super.dispose();
  }
}
