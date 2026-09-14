import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'auth_models.dart';
import 'secure_token_store.dart';
import 'profile_options.dart';

enum SessionRestoreResult { authenticated, noSession, unavailable }

class AuthStorageException implements Exception {
  const AuthStorageException();

  String get message =>
      'Secure sign-in storage is unavailable. Please try again.';

  @override
  String toString() => message;
}

class AuthService extends ChangeNotifier {
  AuthService({ApiClient? apiClient, SecureTokenStore? tokenStore})
    : _apiClient = apiClient ?? ApiClient(),
      _tokenStore = tokenStore ?? FlutterSecureTokenStore(),
      _ownsApiClient = apiClient == null;

  static const _authPath = '/api/v1/auth';
  static const _currentUserPath = '/api/v1/users/me';

  final ApiClient _apiClient;
  final SecureTokenStore _tokenStore;
  final bool _ownsApiClient;

  AuthUser? _user;
  ProfileOptions? _profileOptions;
  String? _accessToken;
  DateTime? _accessTokenExpiresAt;
  String? _refreshToken;
  DateTime? _refreshTokenExpiresAt;

  AuthUser? get user => _user;
  String? get accessToken => _accessToken;
  DateTime? get accessTokenExpiresAt => _accessTokenExpiresAt;
  DateTime? get refreshTokenExpiresAt => _refreshTokenExpiresAt;
  bool get isAuthenticated => _user != null && _accessToken != null;

  Future<AuthUser> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.postJson(
      '$_authPath/register',
      body: {
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'password': password,
      },
    );
    return _parseUser(_dataOf(response)['user']);
  }

  Future<AuthUser> verifyEmail({
    required String email,
    required String code,
  }) async {
    final response = await _apiClient.postJson(
      '$_authPath/email-verification/verify',
      body: {'email': email, 'code': code},
    );
    final session = _parseSession(_dataOf(response));
    await _persistAndApply(session);
    return session.user;
  }

  Future<void> resendEmailVerification({required String email}) async {
    await _apiClient.postJson(
      '$_authPath/email-verification/resend',
      body: {'email': email},
    );
  }

  Future<AuthUser> login({
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.postJson(
      '$_authPath/login',
      body: {'email': email, 'password': password},
    );
    final session = _parseSession(_dataOf(response));
    await _persistAndApply(session);
    return session.user;
  }

  Future<void> requestPasswordReset({required String email}) async {
    await _apiClient.postJson(
      '$_authPath/password-reset/request',
      body: {'email': email},
    );
  }

  Future<String> verifyPasswordReset({
    required String email,
    required String code,
  }) async {
    final response = await _apiClient.postJson(
      '$_authPath/password-reset/verify',
      body: {'email': email, 'code': code},
    );
    final resetToken = _dataOf(response)['resetToken'];
    if (resetToken is! String || resetToken.isEmpty) {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'The server returned an invalid response.',
      );
    }
    return resetToken;
  }

  Future<void> resendPasswordReset({required String email}) {
    return requestPasswordReset(email: email);
  }

  Future<void> completePasswordReset({
    required String resetToken,
    required String newPassword,
  }) async {
    await _apiClient.postJson(
      '$_authPath/password-reset/complete',
      body: {'resetToken': resetToken, 'newPassword': newPassword},
    );
    await _clearLocalSession();
  }

  Future<AuthUser> fetchCurrentUser() async {
    final response = await _authenticatedRequest(
      (accessToken) =>
          _apiClient.getJson(_currentUserPath, bearerToken: accessToken),
    );
    final data = _dataOf(response);
    if (data['profileOptions'] != null) {
      _profileOptions = ProfileOptions.fromJson(data['profileOptions']);
    }
    return _applyCurrentUser(data['user']);
  }

  Future<ProfileOptions> fetchProfileOptions() async {
    if (_profileOptions == null) await fetchCurrentUser();
    return _profileOptions ??
        (throw const ApiException(
          code: 'INVALID_RESPONSE',
          message: 'Profile choices are unavailable. Please try again.',
        ));
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await authenticatedPostJson(
      '$_authPath/password/change',
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
    // Server commits the new hash and all-session revocation before responding.
    await _clearLocalSession();
  }

  Future<AuthUser> updateCurrentUserProfile({
    required String firstName,
    required String lastName,
    required String program,
    required String yearLevel,
    required String school,
  }) async {
    final response = await _authenticatedRequest(
      (accessToken) => _apiClient.patchJson(
        _currentUserPath,
        bearerToken: accessToken,
        body: {
          'firstName': firstName,
          'lastName': lastName,
          'program': program,
          'yearLevel': yearLevel,
          'school': school,
        },
      ),
    );
    return _applyCurrentUser(_dataOf(response)['user']);
  }

  Future<Map<String, dynamic>> authenticatedGetJson(String path) {
    return _authenticatedRequest(
      (accessToken) => _apiClient.getJson(path, bearerToken: accessToken),
    );
  }

  Future<Map<String, dynamic>> authenticatedPostJson(
    String path, {
    required Map<String, dynamic> body,
  }) {
    return _authenticatedRequest(
      (accessToken) =>
          _apiClient.postJson(path, bearerToken: accessToken, body: body),
    );
  }

  Future<Map<String, dynamic>> authenticatedPostJsonWithTimeout(
    String path, {
    required Map<String, dynamic> body,
    required Duration timeout,
  }) {
    return _authenticatedRequest(
      (accessToken) => _apiClient.postJson(
        path,
        bearerToken: accessToken,
        body: body,
        requestTimeout: timeout,
      ),
    );
  }

  Future<Map<String, dynamic>> authenticatedPatchJson(
    String path, {
    required Map<String, dynamic> body,
  }) {
    return _authenticatedRequest(
      (accessToken) =>
          _apiClient.patchJson(path, bearerToken: accessToken, body: body),
    );
  }

  Future<Map<String, dynamic>> authenticatedDeleteJson(String path) {
    return _authenticatedRequest(
      (accessToken) => _apiClient.deleteJson(path, bearerToken: accessToken),
    );
  }

  Future<Map<String, dynamic>> authenticatedPostMultipart(
    String path, {
    required Map<String, String> fields,
    required String fileName,
    required String mimeType,
    required Uint8List fileBytes,
    Duration? requestTimeout,
  }) {
    return _authenticatedRequest(
      (accessToken) => _apiClient.postMultipart(
        path,
        bearerToken: accessToken,
        fields: fields,
        fileName: fileName,
        mimeType: mimeType,
        fileBytes: fileBytes,
        requestTimeout: requestTimeout,
      ),
    );
  }

  Future<SessionRestoreResult> restoreSession() async {
    late final String? storedRefreshToken;
    try {
      storedRefreshToken = await _tokenStore.readRefreshToken();
    } catch (_) {
      return SessionRestoreResult.unavailable;
    }

    if (storedRefreshToken == null || storedRefreshToken.isEmpty) {
      return SessionRestoreResult.noSession;
    }

    try {
      await _refreshWith(storedRefreshToken);
      return SessionRestoreResult.authenticated;
    } on ApiException catch (error) {
      if (error.code == 'INVALID_REFRESH_TOKEN' || error.statusCode == 401) {
        await _clearLocalSession();
        return SessionRestoreResult.noSession;
      }
      return SessionRestoreResult.unavailable;
    } catch (_) {
      return SessionRestoreResult.unavailable;
    }
  }

  Future<void> refreshSession() async {
    String? refreshToken = _refreshToken;
    try {
      refreshToken ??= await _tokenStore.readRefreshToken();
    } catch (_) {
      throw const AuthStorageException();
    }
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const ApiException(
        code: 'INVALID_REFRESH_TOKEN',
        message: 'Your session has expired. Please log in again.',
        statusCode: 401,
      );
    }
    await _refreshWith(refreshToken);
  }

  Future<void> logout() async {
    try {
      String? refreshToken = _refreshToken;
      refreshToken ??= await _tokenStore.readRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _apiClient.postJson(
          '$_authPath/logout',
          body: {'refreshToken': refreshToken},
        );
      }
    } finally {
      await _clearLocalSession();
    }
  }

  Future<void> _refreshWith(String refreshToken) async {
    final response = await _apiClient.postJson(
      '$_authPath/refresh',
      body: {'refreshToken': refreshToken},
    );
    await _persistAndApply(_parseSession(_dataOf(response)));
  }

  Future<Map<String, dynamic>> _authenticatedRequest(
    Future<Map<String, dynamic>> Function(String accessToken) request,
  ) async {
    await _ensureFreshAccessToken();

    try {
      return await request(_requiredAccessToken());
    } on ApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      await _refreshAfterUnauthorized();
      return request(_requiredAccessToken());
    }
  }

  Future<void> _ensureFreshAccessToken() async {
    if (_accessToken == null || _accessToken!.isEmpty) {
      throw const ApiException(
        code: 'UNAUTHORIZED',
        message: 'Your session has expired. Please log in again.',
        statusCode: 401,
      );
    }

    final expiresAt = _accessTokenExpiresAt;
    if (expiresAt == null ||
        !expiresAt.isAfter(DateTime.now().add(const Duration(seconds: 30)))) {
      await _refreshAfterUnauthorized();
    }
  }

  Future<void> _refreshAfterUnauthorized() async {
    try {
      await refreshSession();
    } on ApiException catch (error) {
      if (error.code == 'INVALID_REFRESH_TOKEN' || error.statusCode == 401) {
        try {
          await _clearLocalSession();
        } on AuthStorageException {
          // The in-memory session is already cleared even if secure deletion fails.
        }
      }
      rethrow;
    }
  }

  String _requiredAccessToken() {
    final accessToken = _accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw const ApiException(
        code: 'UNAUTHORIZED',
        message: 'Your session has expired. Please log in again.',
        statusCode: 401,
      );
    }
    return accessToken;
  }

  AuthUser _applyCurrentUser(Object? value) {
    final user = _parseUser(value);
    _user = user;
    notifyListeners();
    return user;
  }

  Future<void> _persistAndApply(AuthSession session) async {
    try {
      await _tokenStore.writeRefreshToken(session.refreshToken);
    } catch (_) {
      try {
        await _apiClient.postJson(
          '$_authPath/logout',
          body: {'refreshToken': session.refreshToken},
        );
      } catch (_) {
        // The token still expires server-side if best-effort revocation fails.
      }
      try {
        await _tokenStore.deleteRefreshToken();
      } catch (_) {
        // Preserve the original secure-storage failure.
      }
      throw const AuthStorageException();
    }

    _user = session.user;
    _accessToken = session.accessToken;
    _accessTokenExpiresAt = session.accessTokenExpiresAt;
    _refreshToken = session.refreshToken;
    _refreshTokenExpiresAt = session.refreshTokenExpiresAt;
    notifyListeners();
  }

  Future<void> _clearLocalSession() async {
    _user = null;
    _profileOptions = null;
    _accessToken = null;
    _accessTokenExpiresAt = null;
    _refreshToken = null;
    _refreshTokenExpiresAt = null;
    notifyListeners();
    try {
      await _tokenStore.deleteRefreshToken();
    } catch (_) {
      throw const AuthStorageException();
    }
  }

  static Map<String, dynamic> _dataOf(Map<String, dynamic> envelope) {
    final data = envelope['data'];
    if (data is Map<String, dynamic>) return data;
    throw const ApiException(
      code: 'INVALID_RESPONSE',
      message: 'The server returned an invalid response.',
    );
  }

  static AuthUser _parseUser(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'The server returned an invalid response.',
      );
    }
    try {
      return AuthUser.fromJson(value);
    } catch (_) {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'The server returned an invalid response.',
      );
    }
  }

  static AuthSession _parseSession(Map<String, dynamic> data) {
    try {
      return AuthSession.fromData(data);
    } catch (_) {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'The server returned an invalid response.',
      );
    }
  }

  @override
  void dispose() {
    if (_ownsApiClient) _apiClient.close();
    super.dispose();
  }
}
