import 'package:flutter/foundation.dart';

import 'api_client.dart';
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

  Future<void> load({bool force = false}) async {
    if ((loaded && !force) || isLoading || isSaving || _disposed) return;
    final generation = _generation;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _auth.authenticatedGetJson('$_path/template'),
        _auth.authenticatedGetJson('$_path/me'),
      ]);
      if (!_current(generation)) return;
      final parsedTemplate = CollegeReportTemplate.fromJson(
        _data(results[0])['template'] as Map<String, dynamic>,
      );
      final data = _data(results[1]);
      if (data['templateReady'] is! bool || data['hasLegacyReport'] is! bool) {
        throw const FormatException();
      }
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
      // A retry must not replace a draft, including edits made in flight.
      if (!dirty) {
        _answers
          ..clear()
          ..addAll({
            for (final q in parsedTemplate.questions)
              q.key: report?.answers[q.key],
          });
        essay = report?.essay ?? '';
        draftRevision++;
      }
      loaded = true;
    } catch (error) {
      if (_current(generation)) {
        errorMessage = _safeError(error);
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
    if (!loaded || isLoading || isSaving || !templateReady || _disposed) {
      return false;
    }
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
    } catch (error) {
      if (_current(generation)) {
        errorMessage =
            'Your changes were not saved. They are still here. ${_safeError(error)}';
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

  static String _safeError(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 401 ||
          error.statusCode == 403 ||
          error.code == 'UNAUTHORIZED' ||
          error.code == 'INVALID_REFRESH_TOKEN') {
        return 'Your session could not be verified. Please sign in again.';
      }
      if (error.statusCode == 404 || error.code == 'ROUTE_NOT_FOUND') {
        return 'College Report is not available on this server yet. Please contact support.';
      }
      if (error.code == 'COLLEGE_REPORT_NOT_CONFIGURED') {
        return 'College Report is not configured yet. Please contact support, then retry.';
      }
      if (error.code == 'NETWORK_TIMEOUT' ||
          error.code == 'COLD_START_TIMEOUT') {
        return 'The server took too long to respond and may be waking up. Please retry.';
      }
      if (error.code == 'NETWORK_OFFLINE' || error.code == 'NETWORK_ERROR') {
        return 'Network unavailable. Check your connection and retry.';
      }
      if (error.statusCode == 503 ||
          error.statusCode == 502 ||
          error.statusCode == 504) {
        return 'The server is temporarily unavailable. Please retry shortly.';
      }
      if (error.statusCode == 429) {
        return 'Too many requests. Please wait a moment before retrying.';
      }
      if (error.code == 'INVALID_RESPONSE') {
        return 'The server returned an unexpected response. Please retry or contact support.';
      }
    }
    if (error is FormatException || error is TypeError) {
      return 'The server returned an unexpected response. Please retry or contact support.';
    }
    return 'An unexpected College Report error occurred. Please retry or contact support.';
  }

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
