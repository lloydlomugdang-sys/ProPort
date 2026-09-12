import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

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

class ApiClient {
  ApiClient({
    String? baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
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
  }) {
    final headers = _headers(bearerToken: bearerToken);
    return _perform(
      () => _client.get(_uriFor(path), headers: headers),
      requestTimeout: requestTimeout,
    );
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    required Map<String, dynamic> body,
    String? bearerToken,
    Duration? requestTimeout,
  }) {
    final headers = _headers(bearerToken: bearerToken, hasJsonBody: true);
    return _perform(
      () =>
          _client.post(_uriFor(path), headers: headers, body: jsonEncode(body)),
      requestTimeout: requestTimeout,
    );
  }

  Future<Map<String, dynamic>> patchJson(
    String path, {
    required Map<String, dynamic> body,
    String? bearerToken,
    Duration? requestTimeout,
  }) {
    final headers = _headers(bearerToken: bearerToken, hasJsonBody: true);
    return _perform(
      () => _client.patch(
        _uriFor(path),
        headers: headers,
        body: jsonEncode(body),
      ),
      requestTimeout: requestTimeout,
    );
  }

  Future<Map<String, dynamic>> deleteJson(
    String path, {
    String? bearerToken,
    Duration? requestTimeout,
  }) {
    final headers = _headers(bearerToken: bearerToken);
    return _perform(
      () => _client.delete(_uriFor(path), headers: headers),
      requestTimeout: requestTimeout,
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
    }, requestTimeout: requestTimeout);
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  static Future<Map<String, dynamic>> _getWithDefaultClient(String path) async {
    final client = ApiClient();
    try {
      return await client.getJson(path);
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> _perform(
    Future<http.Response> Function() request, {
    Duration? requestTimeout,
  }) async {
    late final http.Response response;
    try {
      response = await request().timeout(requestTimeout ?? timeout);
    } on TimeoutException {
      throw const ApiException(
        code: 'NETWORK_TIMEOUT',
        message: 'The server took too long to respond. Please try again.',
      );
    } on http.ClientException {
      throw const ApiException(
        code: 'NETWORK_ERROR',
        message:
            'Unable to reach the server. Check your connection and try again.',
      );
    }

    final decoded = _decodeObject(response.body, response.statusCode);
    if (response.statusCode >= 200 && response.statusCode < 300) {
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

    final error = decoded['error'];
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

    throw ApiException(
      code: 'REQUEST_FAILED',
      message: _fallbackErrorMessage(response.statusCode),
      statusCode: response.statusCode,
      retryAfter: _parseRetryAfter(response.headers['retry-after']),
    );
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
