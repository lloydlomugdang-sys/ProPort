import 'package:flutter/foundation.dart';

import '../screens/portfolio/models/portfolio_models.dart';
import 'api_client.dart';
import 'auth_service.dart';

class PortfolioService extends ChangeNotifier {
  PortfolioService({required AuthService authService})
    : _authService = authService,
      _authenticatedUserId = authService.user?.id {
    _authService.addListener(_handleAuthChanged);
  }

  static const _portfoliosPath = '/api/v1/portfolios';

  final AuthService _authService;
  String? _authenticatedUserId;
  List<PortfolioRecord> _portfolios = const [];
  bool _hasLoaded = false;
  bool _isLoading = false;
  int _generation = 0;
  bool _disposed = false;
  Future<List<PortfolioRecord>>? _pendingLoad;

  List<PortfolioRecord> get portfolios => List.unmodifiable(_portfolios);
  bool get hasLoaded => _hasLoaded;
  bool get isLoading => _isLoading;

  Future<List<PortfolioRecord>> loadPortfolios({bool force = false}) {
    if (_disposed) return Future.value(const []);
    if (_pendingLoad != null) return _pendingLoad!;
    if (_hasLoaded && !force) return Future.value(portfolios);
    return _pendingLoad = _loadPortfolios();
  }

  Future<List<PortfolioRecord>> _loadPortfolios() async {
    _isLoading = true;
    final generation = _generation;
    notifyListeners();
    try {
      final response = await _authService.authenticatedGetJson(_portfoliosPath);
      if (_disposed || generation != _generation) return const [];
      final values = _dataOf(response)['portfolios'];
      if (values is! List) throw _invalidResponse();
      _portfolios = values.map(_parsePortfolio).toList(growable: false);
      _hasLoaded = true;
      return portfolios;
    } finally {
      if (!_disposed && generation == _generation) {
        _pendingLoad = null;
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<PortfolioRecord> getPortfolio(String portfolioId) async {
    final response = await _authService.authenticatedGetJson(
      '$_portfoliosPath/$portfolioId',
    );
    return _upsert(_parsePortfolio(_dataOf(response)['portfolio']));
  }

  Future<PortfolioRecord> createPortfolio(PortfolioInfo info) async {
    _validate(info);
    final response = await _authService.authenticatedPostJson(
      _portfoliosPath,
      body: info.normalizedMap,
    );
    final portfolio = _parsePortfolio(_dataOf(response)['portfolio']);
    _portfolios = [
      portfolio,
      ..._portfolios.where((value) => value.id != portfolio.id),
    ];
    _hasLoaded = true;
    notifyListeners();
    return portfolio;
  }

  Future<PortfolioRecord> updatePortfolio(
    String portfolioId,
    PortfolioInfo info,
  ) async {
    _validate(info);
    final response = await _authService.authenticatedPatchJson(
      '$_portfoliosPath/$portfolioId',
      body: info.normalizedMap,
    );
    return _upsert(_parsePortfolio(_dataOf(response)['portfolio']));
  }

  Future<void> deletePortfolio(String portfolioId) async {
    await _authService.authenticatedDeleteJson('$_portfoliosPath/$portfolioId');
    _portfolios = _portfolios
        .where((portfolio) => portfolio.id != portfolioId)
        .toList(growable: false);
    _hasLoaded = true;
    notifyListeners();
  }

  static void _validate(PortfolioInfo info) {
    final errors = info.validationErrors;
    if (errors.isNotEmpty) {
      throw ApiException(
        code: 'VALIDATION_ERROR',
        message: errors.values.first,
        fields: {
          for (final entry in errors.entries) entry.key: [entry.value],
        },
      );
    }
  }

  PortfolioRecord _upsert(PortfolioRecord portfolio) {
    final updated = [
      portfolio,
      ..._portfolios.where((item) => item.id != portfolio.id),
    ]..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    _portfolios = updated;
    notifyListeners();
    return portfolio;
  }

  void _handleAuthChanged() {
    final userId = _authService.user?.id;
    if (userId == _authenticatedUserId) return;
    _authenticatedUserId = userId;
    _generation++;
    _pendingLoad = null;
    _portfolios = const [];
    _hasLoaded = false;
    _isLoading = false;
    notifyListeners();
  }

  static Map<String, dynamic> _dataOf(Map<String, dynamic> envelope) {
    final data = envelope['data'];
    if (data is Map<String, dynamic>) return data;
    throw _invalidResponse();
  }

  static PortfolioRecord _parsePortfolio(Object? value) {
    if (value is! Map<String, dynamic>) throw _invalidResponse();
    try {
      return PortfolioRecord.fromJson(value);
    } catch (_) {
      throw _invalidResponse();
    }
  }

  static ApiException _invalidResponse() => const ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The server returned an invalid response.',
  );

  @override
  void dispose() {
    _disposed = true;
    _authService.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
