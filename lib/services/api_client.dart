import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// Explicit timeout categories matching GradPort's physical device & hosting architecture.
class ApiTimeoutPolicy {
  const ApiTimeoutPolicy._();

  /// Fast read operations when server is warm (15 seconds).
  static const Duration quickRead = Duration(seconds: 15);

  /// Cold-start tolerant timeout for auth, session restore, and initial loads (60 seconds).
  static const Duration coldStartTolerant = Duration(seconds: 60);

  /// Standard non-upload mutations e.g. profile, portfolio creation/updates (30 seconds).
  static const Duration mutation = Duration(seconds: 30);

  /// Document uploads up to 15 MB over real mobile connections (120 seconds).
  static const Duration upload = Duration(seconds: 120);

  /// Stored document OCR text extraction (60 seconds).
  static const Duration ocr = Duration(seconds: 60);

  /// Pre-upload OCR + AI metadata analysis preview (120 seconds).
  static const Duration preview = Duration(seconds: 120);
}

class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.fields = const {},
    this.retryAfter,
  });

  final String code;
  final String message;
  final int? statusCode;
  final Map<String, dynamic> fields;
  final Duration? retryAfter;

  bool get isTransient => statusCode == null || statusCode! >= 500;

  @override
  String toString() => message;
}

class ApiMultipartFile {
  const ApiMultipartFile({
    required this.field,
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  final String field;
  final String fileName;
  final String mimeType;
  final Uint8List bytes;
}

class ApiClient {
  ApiClient({
    String? baseUrl,
    http.Client? client,
    this.timeout = ApiTimeoutPolicy.quickRead,
  }) : _baseUri = Uri.parse(_resolveBaseUrl(baseUrl)),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  static const String _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
  );
  static const String _developmentBaseUrl = 'http://127.0.0.1:3000';

  /// The effective build-time API URL. Local loopback is a debug-only default.
  static String get baseUrl => _resolveBaseUrl(null);

  @visibleForTesting
  static String resolveBaseUrlForMode(
    String? override, {
    required bool releaseMode,
  }) {
    return _resolveBaseUrl(override, releaseMode: releaseMode);
  }

  final Uri _baseUri;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  @visibleForTesting
  static Duration? retryDelayOverride;

  static Future<Map<String, dynamic>> getHealth() {
    return _getWithDefaultClient('/health');
  }

  static Future<Map<String, dynamic>> getReady() {
    return _getWithDefaultClient('/ready');
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    String? bearerToken,
    Duration? requestTimeout,
    bool autoRetry = true,
  }) {
    final headers = _headers(bearerToken: bearerToken);
    return _perform(
      () => _client.get(_uriFor(path), headers: headers),
      requestTimeout: requestTimeout,
      autoRetry: autoRetry,
      method: 'GET',
      path: path,
    );
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    required Map<String, dynamic> body,
    String? bearerToken,
    Duration? requestTimeout,
  }) {
    final effectiveTimeout = requestTimeout ??
        (timeout == ApiTimeoutPolicy.quickRead
            ? ApiTimeoutPolicy.mutation
            : timeout);
    final headers = _headers(bearerToken: bearerToken, hasJsonBody: true);
    return _perform(
      () =>
          _client.post(_uriFor(path), headers: headers, body: jsonEncode(body)),
      requestTimeout: effectiveTimeout,
      autoRetry: false,
      method: 'POST',
      path: path,
    );
  }

  Future<Map<String, dynamic>> patchJson(
    String path, {
    required Map<String, dynamic> body,
    String? bearerToken,
    Duration? requestTimeout,
  }) {
    final effectiveTimeout = requestTimeout ??
        (timeout == ApiTimeoutPolicy.quickRead
            ? ApiTimeoutPolicy.mutation
            : timeout);
    final headers = _headers(bearerToken: bearerToken, hasJsonBody: true);
    return _perform(
      () => _client.patch(
        _uriFor(path),
        headers: headers,
        body: jsonEncode(body),
      ),
      requestTimeout: effectiveTimeout,
      autoRetry: false,
      method: 'PATCH',
      path: path,
    );
  }

  Future<Map<String, dynamic>> deleteJson(
    String path, {
    String? bearerToken,
    Duration? requestTimeout,
  }) {
    final effectiveTimeout = requestTimeout ??
        (timeout == ApiTimeoutPolicy.quickRead
            ? ApiTimeoutPolicy.mutation
            : timeout);
    final headers = _headers(bearerToken: bearerToken);
    return _perform(
      () => _client.delete(_uriFor(path), headers: headers),
      requestTimeout: effectiveTimeout,
      autoRetry: false,
      method: 'DELETE',
      path: path,
    );
  }

  Future<Uint8List> getBytes(
    String path, {
    String? bearerToken,
    Duration? requestTimeout,
    bool autoRetry = true,
  }) async {
    final effectiveTimeout = requestTimeout ?? timeout;
    final headers = _headers(bearerToken: bearerToken);
    final maxAttempts = autoRetry ? 2 : 1;
    int attempt = 0;

    while (attempt < maxAttempts) {
      attempt++;
      final stopwatch = Stopwatch()..start();
      http.Response? response;
      Object? caughtException;

      try {
        response = await _client
            .get(_uriFor(path), headers: headers)
            .timeout(effectiveTimeout);
      } on TimeoutException catch (e) {
        caughtException = e;
      } on SocketException catch (e) {
        caughtException = e;
      } on http.ClientException catch (e) {
        caughtException = e;
      }

      stopwatch.stop();

      final isServerWaking = response != null &&
          (response.statusCode == 502 ||
              response.statusCode == 503 ||
              response.statusCode == 504);

      final isTransientError =
          isServerWaking || caughtException is http.ClientException;

      if (autoRetry && attempt < maxAttempts && isTransientError) {
        _logRequest(
          method: 'GET',
          path: path,
          durationMs: stopwatch.elapsedMilliseconds,
          statusCode: response?.statusCode,
          retryCount: attempt,
          error: 'Transient error, retrying',
        );
        await Future<void>.delayed(
          retryDelayOverride ?? const Duration(milliseconds: 500),
        );
        continue;
      }

      if (caughtException != null) {
        _logRequest(
          method: 'GET',
          path: path,
          durationMs: stopwatch.elapsedMilliseconds,
          error: caughtException.runtimeType.toString(),
        );

        if (caughtException is TimeoutException) {
          if (effectiveTimeout >= const Duration(seconds: 45)) {
            throw const ApiException(
              code: 'COLD_START_TIMEOUT',
              message:
                  'The server is taking longer than usual to wake up. Please try again in a few moments.',
            );
          }
          throw const ApiException(
            code: 'NETWORK_TIMEOUT',
            message: 'The server took too long to respond. Please try again.',
          );
        }

        if (caughtException is SocketException) {
          throw const ApiException(
            code: 'NETWORK_OFFLINE',
            message:
                'No internet connection. Please check your network and try again.',
          );
        }

        if (caughtException is http.ClientException) {
          final msg = caughtException.message.toLowerCase();
          if (msg.contains('failed host lookup') ||
              msg.contains('no route to host') ||
              msg.contains('network is unreachable') ||
              msg.contains('connection refused')) {
            throw const ApiException(
              code: 'NETWORK_OFFLINE',
              message:
                  'No internet connection. Please check your network and try again.',
            );
          }
          throw const ApiException(
            code: 'NETWORK_ERROR',
            message:
                'Unable to reach the server. Check your connection and try again.',
          );
        }
      }

      _logRequest(
        method: 'GET',
        path: path,
        durationMs: stopwatch.elapsedMilliseconds,
        statusCode: response!.statusCode,
        retryCount: attempt - 1,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }

      final decoded = _tryDecodeObject(response.body);
      final error = decoded?['error'];
      if (error is Map<String, dynamic>) {
        final rawFields = error['fields'];
        throw ApiException(
          code: error['code'] is String
              ? error['code'] as String
              : 'UNKNOWN_ERROR',
          message: error['message'] is String
              ? error['message'] as String
              : 'An error occurred.',
          statusCode: response.statusCode,
          fields: rawFields is Map<String, dynamic> ? rawFields : const {},
          retryAfter: _parseRetryAfter(response.headers['retry-after']),
        );
      }

      if (isServerWaking) {
        throw ApiException(
          code: 'SERVER_WAKING',
          message:
              'The server is waking up. Please wait a moment and try again.',
          statusCode: response.statusCode,
          retryAfter: _parseRetryAfter(response.headers['retry-after']),
        );
      }

      throw ApiException(
        code: 'HTTP_${response.statusCode}',
        message: 'Request failed with status ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }

    throw const ApiException(
      code: 'NETWORK_TIMEOUT',
      message: 'The server took too long to respond. Please try again.',
    );
  }

  Future<Uint8List> postBytes(
    String path, {
    required Map<String, dynamic> body,
    String? bearerToken,
    Duration? requestTimeout,
  }) async {
    final effectiveTimeout = requestTimeout ??
        (timeout == ApiTimeoutPolicy.quickRead
            ? ApiTimeoutPolicy.mutation
            : timeout);
    final headers = _headers(bearerToken: bearerToken, hasJsonBody: true);
    final stopwatch = Stopwatch()..start();
    late final http.Response response;

    try {
      response = await _client
          .post(_uriFor(path), headers: headers, body: jsonEncode(body))
          .timeout(effectiveTimeout);
    } on TimeoutException {
      stopwatch.stop();
      _logRequest(
        method: 'POST',
        path: path,
        durationMs: stopwatch.elapsedMilliseconds,
        error: 'TimeoutException',
      );
      if (effectiveTimeout >= const Duration(seconds: 45)) {
        throw const ApiException(
          code: 'COLD_START_TIMEOUT',
          message:
              'The server is taking longer than usual to wake up. Please try again in a few moments.',
        );
      }
      throw const ApiException(
        code: 'NETWORK_TIMEOUT',
        message: 'The server took too long to respond. Please try again.',
      );
    } on SocketException {
      stopwatch.stop();
      _logRequest(
        method: 'POST',
        path: path,
        durationMs: stopwatch.elapsedMilliseconds,
        error: 'SocketException',
      );
      throw const ApiException(
        code: 'NETWORK_OFFLINE',
        message:
            'No internet connection. Please check your network and try again.',
      );
    } on http.ClientException catch (e) {
      stopwatch.stop();
      _logRequest(
        method: 'POST',
        path: path,
        durationMs: stopwatch.elapsedMilliseconds,
        error: 'ClientException',
      );
      final msg = e.message.toLowerCase();
      if (msg.contains('failed host lookup') ||
          msg.contains('no route to host') ||
          msg.contains('network is unreachable') ||
          msg.contains('connection refused')) {
        throw const ApiException(
          code: 'NETWORK_OFFLINE',
          message:
              'No internet connection. Please check your network and try again.',
        );
      }
      throw const ApiException(
        code: 'NETWORK_ERROR',
        message:
            'Unable to reach the server. Check your connection and try again.',
      );
    }

    stopwatch.stop();
    _logRequest(
      method: 'POST',
      path: path,
      durationMs: stopwatch.elapsedMilliseconds,
      statusCode: response.statusCode,
    );

    if (response.statusCode >= 502 && response.statusCode <= 504) {
      throw ApiException(
        code: 'SERVER_WAKING',
        message: 'The server is waking up. Please wait a moment and try again.',
        statusCode: response.statusCode,
        retryAfter: _parseRetryAfter(response.headers['retry-after']),
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }

    final decoded = _decodeObject(response.body, response.statusCode);
    final error = decoded['error'];
    if (error is Map<String, dynamic>) {
      final rawFields = error['fields'];
      throw ApiException(
        code: error['code'] is String
            ? error['code'] as String
            : 'UNKNOWN_ERROR',
        message: error['message'] is String
            ? error['message'] as String
            : 'An error occurred.',
        statusCode: response.statusCode,
        fields: rawFields is Map<String, dynamic> ? rawFields : const {},
        retryAfter: _parseRetryAfter(response.headers['retry-after']),
      );
    }
    throw ApiException(
      code: 'HTTP_${response.statusCode}',
      message: 'Request failed with status ${response.statusCode}.',
      statusCode: response.statusCode,
    );
  }

  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required Map<String, String> fields,
    required String fileName,
    required String mimeType,
    required Uint8List fileBytes,
    String? bearerToken,
    Duration? requestTimeout,
  }) {
    return _perform(() async {
      final request = http.MultipartRequest('POST', _uriFor(path));
      request.headers.addAll(_headers(bearerToken: bearerToken));
      request.fields.addAll(fields);
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName,
          contentType: MediaType.parse(mimeType),
        ),
      );
      return http.Response.fromStream(await _client.send(request));
    }, requestTimeout: requestTimeout, autoRetry: false, method: 'POST', path: path);
  }

  Future<Map<String, dynamic>> postMultiPartFiles(
    String path, {
    required Map<String, String> fields,
    required List<ApiMultipartFile> files,
    String? bearerToken,
    Duration? requestTimeout,
  }) {
    return _perform(() async {
      final request = http.MultipartRequest('POST', _uriFor(path));
      request.headers.addAll(_headers(bearerToken: bearerToken));
      request.fields.addAll(fields);
      for (final f in files) {
        request.files.add(
          http.MultipartFile.fromBytes(
            f.field,
            f.bytes,
            filename: f.fileName,
            contentType: MediaType.parse(f.mimeType),
          ),
        );
      }
      return http.Response.fromStream(await _client.send(request));
    }, requestTimeout: requestTimeout, autoRetry: false, method: 'POST', path: path);
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  static Future<Map<String, dynamic>> _getWithDefaultClient(String path) async {
    final client = ApiClient(timeout: ApiTimeoutPolicy.coldStartTolerant);
    try {
      return await client.getJson(path, autoRetry: true);
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> _perform(
    Future<http.Response> Function() request, {
    Duration? requestTimeout,
    bool autoRetry = false,
    String? method,
    String? path,
  }) async {
    final effectiveTimeout = requestTimeout ?? timeout;
    final maxAttempts = autoRetry ? 2 : 1;
    int attempt = 0;

    while (attempt < maxAttempts) {
      attempt++;
      final stopwatch = Stopwatch()..start();
      http.Response? response;
      Object? caughtException;

      try {
        response = await request().timeout(effectiveTimeout);
      } on TimeoutException catch (e) {
        caughtException = e;
      } on SocketException catch (e) {
        caughtException = e;
      } on http.ClientException catch (e) {
        caughtException = e;
      }

      stopwatch.stop();

      final isServerWaking = response != null &&
          (response.statusCode == 502 ||
              response.statusCode == 503 ||
              response.statusCode == 504);

      final isTransientError =
          isServerWaking || caughtException is http.ClientException;

      if (autoRetry && attempt < maxAttempts && isTransientError) {
        _logRequest(
          method: method ?? 'UNKNOWN',
          path: path ?? '',
          durationMs: stopwatch.elapsedMilliseconds,
          statusCode: response?.statusCode,
          retryCount: attempt,
          error: 'Transient error, retrying',
        );
        await Future<void>.delayed(
          retryDelayOverride ?? const Duration(milliseconds: 500),
        );
        continue;
      }

      if (caughtException != null) {
        _logRequest(
          method: method ?? 'UNKNOWN',
          path: path ?? '',
          durationMs: stopwatch.elapsedMilliseconds,
          error: caughtException.runtimeType.toString(),
        );

        if (caughtException is TimeoutException) {
          if (effectiveTimeout >= const Duration(seconds: 45)) {
            throw const ApiException(
              code: 'COLD_START_TIMEOUT',
              message:
                  'The server is taking longer than usual to wake up. Please try again in a few moments.',
            );
          }
          throw const ApiException(
            code: 'NETWORK_TIMEOUT',
            message: 'The server took too long to respond. Please try again.',
          );
        }

        if (caughtException is SocketException) {
          throw const ApiException(
            code: 'NETWORK_OFFLINE',
            message:
                'No internet connection. Please check your network and try again.',
          );
        }

        if (caughtException is http.ClientException) {
          final msg = caughtException.message.toLowerCase();
          if (msg.contains('failed host lookup') ||
              msg.contains('no route to host') ||
              msg.contains('network is unreachable') ||
              msg.contains('connection refused')) {
            throw const ApiException(
              code: 'NETWORK_OFFLINE',
              message:
                  'No internet connection. Please check your network and try again.',
            );
          }
          throw const ApiException(
            code: 'NETWORK_ERROR',
            message:
                'Unable to reach the server. Check your connection and try again.',
          );
        }
      }

      _logRequest(
        method: method ?? 'UNKNOWN',
        path: path ?? '',
        durationMs: stopwatch.elapsedMilliseconds,
        statusCode: response!.statusCode,
        retryCount: attempt - 1,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = _decodeObject(response.body, response.statusCode);
        final meta = decoded['meta'];
        if (decoded['data'] is! Map<String, dynamic> ||
            meta is! Map<String, dynamic> ||
            meta['requestId'] is! String) {
          throw ApiException(
            code: 'INVALID_RESPONSE',
            message: 'The server returned an invalid response.',
            statusCode: response.statusCode,
          );
        }
        return decoded;
      }

      final decoded = _tryDecodeObject(response.body);
      final error = decoded?['error'];
      if (error is Map<String, dynamic>) {
        final rawFields = error['fields'];
        throw ApiException(
          code: error['code'] is String
              ? error['code'] as String
              : 'REQUEST_FAILED',
          message: error['message'] is String
              ? error['message'] as String
              : _fallbackErrorMessage(response.statusCode),
          statusCode: response.statusCode,
          fields: rawFields is Map<String, dynamic> ? rawFields : const {},
          retryAfter: _parseRetryAfter(response.headers['retry-after']),
        );
      }

      if (isServerWaking) {
        throw ApiException(
          code: 'SERVER_WAKING',
          message:
              'The server is waking up. Please wait a moment and try again.',
          statusCode: response.statusCode,
          retryAfter: _parseRetryAfter(response.headers['retry-after']),
        );
      }

      throw ApiException(
        code: 'REQUEST_FAILED',
        message: _fallbackErrorMessage(response.statusCode),
        statusCode: response.statusCode,
        retryAfter: _parseRetryAfter(response.headers['retry-after']),
      );
    }

    throw const ApiException(
      code: 'NETWORK_TIMEOUT',
      message: 'The server took too long to respond. Please try again.',
    );
  }

  static void _logRequest({
    required String method,
    required String path,
    required int durationMs,
    int? statusCode,
    int retryCount = 0,
    String? error,
  }) {
    if (kDebugMode) {
      final cleanPath = path.split('?').first;
      final retryInfo = retryCount > 0 ? ' [retry: $retryCount]' : '';
      final statusInfo = statusCode != null
          ? ' -> $statusCode'
          : (error != null ? ' -> $error' : '');
      debugPrint(
        '[API] $method $cleanPath (${durationMs}ms)$retryInfo$statusInfo',
      );
    }
  }

  Uri _uriFor(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return _baseUri.resolve(normalizedPath);
  }

  static Map<String, String> _headers({
    String? bearerToken,
    bool hasJsonBody = false,
  }) {
    return {
      'Accept': 'application/json',
      if (hasJsonBody) 'Content-Type': 'application/json',
      if (bearerToken != null) 'Authorization': 'Bearer $bearerToken',
    };
  }

  static Map<String, dynamic>? _tryDecodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  static Map<String, dynamic> _decodeObject(String body, int statusCode) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Converted to a safe protocol error below.
    }
    throw ApiException(
      code: 'INVALID_RESPONSE',
      message: 'The server returned an invalid response.',
      statusCode: statusCode,
    );
  }

  static Duration? _parseRetryAfter(String? value) {
    final seconds = int.tryParse(value ?? '');
    return seconds == null ? null : Duration(seconds: seconds);
  }

  static String _fallbackErrorMessage(int statusCode) {
    if (statusCode >= 500) {
      return 'The server is temporarily unavailable. Please try again.';
    }
    return 'The request could not be completed.';
  }

  static String _resolveBaseUrl(
    String? override, {
    bool releaseMode = kReleaseMode,
  }) {
    final raw = (override ?? _configuredBaseUrl).trim();
    final effective = raw.isEmpty ? _developmentBaseUrl : raw;
    final uri = Uri.tryParse(effective);

    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('API_BASE_URL must be an absolute HTTP(S) URL.');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw StateError('API_BASE_URL must use HTTP or HTTPS.');
    }

    if (releaseMode) {
      if (raw.isEmpty) {
        throw StateError('API_BASE_URL is required for release builds.');
      }
      if (uri.scheme != 'https') {
        throw StateError('API_BASE_URL must use HTTPS in release builds.');
      }
      final host = uri.host.toLowerCase();
      if (host == 'localhost' ||
          host == '::1' ||
          host == '10.0.2.2' ||
          host.startsWith('127.') ||
          host.endsWith('.localhost')) {
        throw StateError(
          'API_BASE_URL cannot use a loopback host in release builds.',
        );
      }
    }

    return effective.endsWith('/')
        ? effective.substring(0, effective.length - 1)
        : effective;
  }
}
