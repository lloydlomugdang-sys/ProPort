import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proport_app/services/api_client.dart';

void main() {
  test('postJson sends JSON and returns a valid data envelope', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'data': {'status': 'ok'},
          'meta': {'requestId': 'request-1'},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = ApiClient(baseUrl: 'http://example.test:3000', client: client);

    final response = await api.postJson(
      '/api/v1/auth/login',
      body: {'email': 'student@example.com', 'password': ' raw password '},
    );

    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/v1/auth/login');
    expect(captured.headers['content-type'], 'application/json');
    expect(jsonDecode(captured.body), {
      'email': 'student@example.com',
      'password': ' raw password ',
    });
    expect((response['data'] as Map<String, dynamic>)['status'], 'ok');
  });

  test('patchJson sends the bearer token and JSON profile fields', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'data': {'status': 'ok'},
          'meta': {'requestId': 'request-profile'},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = ApiClient(baseUrl: 'http://example.test:3000', client: client);

    await api.patchJson(
      '/api/v1/users/me',
      bearerToken: 'access-token',
      body: {'program': 'Information Technology'},
    );

    expect(captured.method, 'PATCH');
    expect(captured.url.path, '/api/v1/users/me');
    expect(captured.headers['authorization'], 'Bearer access-token');
    expect(jsonDecode(captured.body), {'program': 'Information Technology'});
  });

  test('deleteJson sends the bearer token without a request body', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'data': {'status': 'deleted', 'portfolioId': 'portfolio-1'},
          'meta': {'requestId': 'request-delete'},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = ApiClient(baseUrl: 'http://example.test:3000', client: client);

    await api.deleteJson(
      '/api/v1/portfolios/portfolio-1',
      bearerToken: 'access-token',
    );

    expect(captured.method, 'DELETE');
    expect(captured.url.path, '/api/v1/portfolios/portfolio-1');
    expect(captured.headers['authorization'], 'Bearer access-token');
    expect(captured.body, isEmpty);
  });

  test(
    'postMultipart sends metadata, file bytes, MIME type, and bearer token',
    () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'data': {
              'document': {'id': 'document-1'},
            },
            'meta': {'requestId': 'request-upload'},
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = ApiClient(
        baseUrl: 'http://example.test:3000',
        client: client,
      );

      await api.postMultipart(
        '/api/v1/documents',
        bearerToken: 'access-token',
        fields: const {
          'categoryKey': 'certificates',
          'folderKey': 'seminars',
          'title': 'Demo Certificate',
          'documentDate': '2026-09-11',
        },
        fileName: 'demo.pdf',
        mimeType: 'application/pdf',
        fileBytes: Uint8List.fromList('%PDF-GradPort'.codeUnits),
      );

      final contentType = captured.headers['content-type']!;
      expect(captured.method, 'POST');
      expect(captured.url.path, '/api/v1/documents');
      expect(captured.headers['authorization'], 'Bearer access-token');
      expect(contentType, startsWith('multipart/form-data; boundary='));
      expect(captured.body, contains('name="categoryKey"'));
      expect(captured.body, contains('certificates'));
      expect(captured.body, contains('filename="demo.pdf"'));
      expect(captured.body, contains('content-type: application/pdf'));
      expect(captured.body, contains('%PDF-GradPort'));
    },
  );

  test('structured API failures become safe ApiException values', () async {
    final client = MockClient((_) async {
      return http.Response(
        jsonEncode({
          'error': {
            'code': 'RATE_LIMITED',
            'message': 'Please wait before trying again.',
            'requestId': 'request-2',
            'fields': {'email': 'Try again later.'},
          },
        }),
        429,
        headers: {'retry-after': '60'},
      );
    });
    final api = ApiClient(baseUrl: 'http://example.test:3000', client: client);

    final future = api.postJson('/api/v1/auth/login', body: const {});

    await expectLater(
      future,
      throwsA(
        isA<ApiException>()
            .having((error) => error.code, 'code', 'RATE_LIMITED')
            .having((error) => error.statusCode, 'statusCode', 429)
            .having(
              (error) => error.retryAfter,
              'retryAfter',
              const Duration(seconds: 60),
            )
            .having(
              (error) => error.fields['email'],
              'field error',
              'Try again later.',
            ),
      ),
    );
  });

  test('malformed success envelopes are rejected', () async {
    final client = MockClient((_) async => http.Response('{}', 200));
    final api = ApiClient(baseUrl: 'http://example.test:3000', client: client);

    await expectLater(
      api.getJson('/ready'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'INVALID_RESPONSE',
        ),
      ),
    );
  });

  test('success envelopes require request metadata', () async {
    final client = MockClient((_) async {
      return http.Response(jsonEncode({'data': {}}), 200);
    });
    final api = ApiClient(baseUrl: 'http://example.test:3000', client: client);

    await expectLater(
      api.getJson('/ready'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'INVALID_RESPONSE',
        ),
      ),
    );
  });

  test('requests time out with a safe network error', () async {
    final client = MockClient((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return http.Response(
        jsonEncode({
          'data': {},
          'meta': {'requestId': 'request-late'},
        }),
        200,
      );
    });
    final api = ApiClient(
      baseUrl: 'http://example.test:3000',
      client: client,
      timeout: const Duration(milliseconds: 5),
    );

    await expectLater(
      api.getJson('/ready'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'NETWORK_TIMEOUT',
        ),
      ),
    );
  });

  test(
    'a slow OCR request can use a dedicated timeout without changing the default',
    () async {
      final client = MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        return http.Response(
          jsonEncode({
            'data': {
              'ocr': {'status': 'ready'},
            },
            'meta': {'requestId': 'request-ocr'},
          }),
          200,
        );
      });
      final api = ApiClient(
        baseUrl: 'http://example.test:3000',
        client: client,
        timeout: const Duration(milliseconds: 5),
      );

      final response = await api.postJson(
        '/api/v1/documents/document-1/ocr',
        body: const {},
        requestTimeout: const Duration(milliseconds: 100),
      );

      expect(response['data'], isA<Map<String, dynamic>>());
      expect(api.timeout, const Duration(milliseconds: 5));
    },
  );

  group('release API URL policy', () {
    test('accepts only a deployed HTTPS URL', () {
      expect(
        ApiClient.resolveBaseUrlForMode(
          'https://api.gradport.example/',
          releaseMode: true,
        ),
        'https://api.gradport.example',
      );
    });

    for (final invalidUrl in <String>[
      '',
      'not-a-url',
      'http://api.gradport.example',
      'https://localhost:3000',
      'https://127.0.0.1:3000',
      'https://app.localhost',
    ]) {
      test('rejects $invalidUrl', () {
        expect(
          () => ApiClient.resolveBaseUrlForMode(invalidUrl, releaseMode: true),
          throwsStateError,
        );
      });
    }
  });
}
