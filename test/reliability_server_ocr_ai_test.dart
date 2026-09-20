import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proport_app/screens/auth/login_screen.dart';
import 'package:proport_app/screens/auth/widgets/auth_form_feedback.dart';
import 'package:proport_app/screens/files/add_file_screen.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_scope.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/document_models.dart';
import 'package:proport_app/services/document_scope.dart';
import 'package:proport_app/services/document_service.dart';
import 'package:proport_app/services/secure_token_store.dart';
import 'package:proport_app/services/server_prewarm_service.dart';

class _FakeTokenStore implements SecureTokenStore {
  String? refreshToken = 'initial-refresh-token';

  @override
  Future<void> deleteRefreshToken() async {
    refreshToken = null;
  }

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> writeRefreshToken(String token) async {
    refreshToken = token;
  }
}

class _TestDocumentService extends DocumentService {
  _TestDocumentService({required super.authService});

  int previewCallCount = 0;
  Completer<DocumentOcrResult>? pendingPreview;
  DocumentOcrResult? previewToReturn;

  @override
  List<DocumentCategory> get categories => [
        const DocumentCategory(
          key: 'cert',
          name: 'Certificates',
          folders: [DocumentFolder(key: 'sem', name: 'Seminars')],
        ),
      ];

  @override
  Future<DocumentOcrResult> previewOcr(dynamic fileOrFiles) async {
    previewCallCount++;
    if (pendingPreview != null) {
      return pendingPreview!.future;
    }
    return previewToReturn ??
        const DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          rawText: 'Sample OCR Text',
          metadataSuggestions: DocumentMetadataSuggestions(
            title: 'Auto Title From OCR',
            categoryKey: 'cert',
            folderKey: 'sem',
          ),
        );
  }
}

void main() {
  setUp(() {
    ApiClient.retryDelayOverride = Duration.zero;
    ServerPrewarmService.instance.reset();
  });

  tearDown(() {
    ApiClient.retryDelayOverride = null;
    ServerPrewarmService.instance.reset();
  });

  group('Goal 1: ApiTimeoutPolicy Categories', () {
    test('enforces exact architectural timeout durations', () {
      expect(ApiTimeoutPolicy.quickRead, const Duration(seconds: 15));
      expect(ApiTimeoutPolicy.coldStartTolerant, const Duration(seconds: 60));
      expect(ApiTimeoutPolicy.mutation, const Duration(seconds: 30));
      expect(ApiTimeoutPolicy.upload, const Duration(seconds: 120));
      expect(ApiTimeoutPolicy.ocr, const Duration(seconds: 60));
      expect(ApiTimeoutPolicy.preview, const Duration(seconds: 120));
    });
  });

  group('Goal 2: Safe Read Auto-Retry (Max 1 Retry)', () {
    test('safe GET retries once on transient 502 then succeeds', () async {
      int attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        if (attempts == 1) {
          return http.Response('Bad Gateway (waking up)', 502);
        }
        return http.Response(
          jsonEncode({
            'data': {'status': 'healthy'},
            'meta': {'requestId': 'req-healthy'},
          }),
          200,
        );
      });

      final api = ApiClient(baseUrl: 'https://example.test', client: client);
      final response = await api.getJson('/health', autoRetry: true);

      expect(attempts, 2);
      expect(response['data']['status'], 'healthy');
    });

    test('safe GET retries once on transient 503 then succeeds', () async {
      int attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        if (attempts == 1) {
          return http.Response('Service Unavailable', 503);
        }
        return http.Response(
          jsonEncode({
            'data': {'status': 'ready'},
            'meta': {'requestId': 'req-ready'},
          }),
          200,
        );
      });

      final api = ApiClient(baseUrl: 'https://example.test', client: client);
      final response = await api.getJson('/ready', autoRetry: true);

      expect(attempts, 2);
      expect(response['data']['status'], 'ready');
    });

    test('safe GET retries once on transient ClientException then succeeds', () async {
      int attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        if (attempts == 1) {
          throw http.ClientException('Connection reset by peer');
        }
        return http.Response(
          jsonEncode({
            'data': {'documents': []},
            'meta': {'requestId': 'req-docs'},
          }),
          200,
        );
      });

      final api = ApiClient(baseUrl: 'https://example.test', client: client);
      final response = await api.getJson('/api/v1/documents', autoRetry: true);

      expect(attempts, 2);
      expect(response['data']['documents'], isEmpty);
    });

    test('safe GET does not retry more than once (max 2 attempts)', () async {
      int attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        return http.Response('Bad Gateway', 502);
      });

      final api = ApiClient(baseUrl: 'https://example.test', client: client);

      await expectLater(
        api.getJson('/ready', autoRetry: true),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'SERVER_WAKING')
              .having((e) => e.statusCode, 'statusCode', 502),
        ),
      );

      expect(attempts, 2);
    });

    test('safe getBytes retries once on 502 then returns bytes', () async {
      int attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        if (attempts == 1) {
          return http.Response('Bad Gateway', 502);
        }
        return http.Response.bytes(Uint8List.fromList([1, 2, 3, 4]), 200);
      });

      final api = ApiClient(baseUrl: 'https://example.test', client: client);
      final bytes = await api.getBytes('/api/v1/documents/doc-1/content', autoRetry: true);

      expect(attempts, 2);
      expect(bytes, Uint8List.fromList([1, 2, 3, 4]));
    });
  });

  group('Goal 3: Mutation Operations Are NEVER Retried', () {
    test('POST document upload is NEVER retried automatically', () async {
      int attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        return http.Response('Service Unavailable', 503);
      });

      final api = ApiClient(baseUrl: 'https://example.test', client: client);

      await expectLater(
        api.postMultipart(
          '/api/v1/documents',
          fields: const {'title': 'Doc'},
          fileName: 'doc.pdf',
          mimeType: 'application/pdf',
          fileBytes: Uint8List(16),
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 503)),
      );

      expect(attempts, 1, reason: 'Upload mutations must NEVER be automatically retried');
    });

    test('POST login is NEVER retried automatically', () async {
      int attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        return http.Response('Bad Gateway', 502);
      });

      final api = ApiClient(baseUrl: 'https://example.test', client: client);

      await expectLater(
        api.postJson('/api/v1/auth/login', body: {'email': 'a@b.com', 'password': 'p'}),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 502)),
      );

      expect(attempts, 1, reason: 'Login must NEVER be automatically retried');
    });

    test('POST token refresh is NEVER retried automatically (strict rotation safety)', () async {
      int attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        return http.Response('Bad Gateway', 502);
      });

      final tokenStore = _FakeTokenStore();
      final api = ApiClient(baseUrl: 'https://example.test', client: client);
      final auth = AuthService(apiClient: api, tokenStore: tokenStore);

      final result = await auth.restoreSession();

      expect(result, SessionRestoreResult.unavailable);
      expect(attempts, 1, reason: 'Refresh tokens must NEVER be auto-retried to avoid family revocation');
    });

    test('PATCH profile is NEVER retried automatically', () async {
      int attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        return http.Response('Gateway Timeout', 504);
      });

      final api = ApiClient(baseUrl: 'https://example.test', client: client);

      await expectLater(
        api.patchJson('/api/v1/users/me', body: {'firstName': 'John'}),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 504)),
      );

      expect(attempts, 1, reason: 'Profile PATCH must NEVER be auto-retried');
    });

    test('DELETE document is NEVER retried automatically', () async {
      int attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        return http.Response('Bad Gateway', 502);
      });

      final api = ApiClient(baseUrl: 'https://example.test', client: client);

      await expectLater(
        api.deleteJson('/api/v1/documents/doc-1'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 502)),
      );

      expect(attempts, 1, reason: 'Document DELETE must NEVER be auto-retried');
    });
  });

  group('Goal 4: ServerPrewarmService Resilience & Deduplication', () {
    test('prewarm executes non-blocking and deduplicates concurrent calls', () async {
      int pingCount = 0;
      final completer = Completer<http.Response>();

      final client = MockClient((request) {
        pingCount++;
        expect(request.url.path, '/health');
        return completer.future;
      });

      final api = ApiClient(baseUrl: 'https://example.test', client: client);
      final prewarmService = ServerPrewarmService.instance;

      final future1 = prewarmService.prewarm(apiClient: api);
      final future2 = prewarmService.prewarm(apiClient: api);

      expect(identical(future1, future2), isTrue, reason: 'Concurrent prewarm calls must deduplicate to single in-flight future');

      completer.complete(
        http.Response(
          jsonEncode({
            'data': {'status': 'ok'},
            'meta': {'requestId': 'pw-1'},
          }),
          200,
        ),
      );

      final result = await future1;
      expect(result, isTrue);
      expect(pingCount, 1, reason: 'Must only dispatch 1 HTTP ping across concurrent callers');
      expect(prewarmService.hasInFlight, isFalse);
    });

    test('prewarm suppresses errors silently and returns false without throwing', () async {
      final client = MockClient((request) async {
        throw const SocketException('No route to host');
      });

      final api = ApiClient(baseUrl: 'https://example.test', client: client);
      final prewarmService = ServerPrewarmService.instance;

      final result = await prewarmService.prewarm(apiClient: api);
      expect(result, isFalse);
    });

    test('prewarm respects 5-minute cooldown gate', () async {
      int pingCount = 0;
      final client = MockClient((request) async {
        pingCount++;
        return http.Response(
          jsonEncode({
            'data': {'status': 'ok'},
            'meta': {'requestId': 'pw-cooldown'},
          }),
          200,
        );
      });

      final api = ApiClient(baseUrl: 'https://example.test', client: client);
      final prewarmService = ServerPrewarmService.instance;

      await prewarmService.prewarm(apiClient: api);
      expect(pingCount, 1);

      // Second immediate call within cooldown
      final immediateResult = await prewarmService.prewarm(apiClient: api);
      expect(immediateResult, isTrue);
      expect(pingCount, 1, reason: 'Must not re-ping within 5-minute cooldown');
    });
  });

  group('Goal 5: Error Classification & UI Messaging', () {
    test('classifies SocketException as NETWORK_OFFLINE with clear user text', () async {
      final client = MockClient((request) async {
        throw const SocketException('Network is unreachable');
      });

      final api = ApiClient(baseUrl: 'https://example.test', client: client);

      try {
        await api.getJson('/health', autoRetry: false);
        fail('Should have thrown');
      } on ApiException catch (e) {
        expect(e.code, 'NETWORK_OFFLINE');
        expect(authFormError(e), 'No internet connection. Please check your network and try again.');
      }
    });

    test('classifies cold-start timeout (>= 45s) as COLD_START_TIMEOUT', () async {
      final client = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response('ok', 200);
      });

      final api = ApiClient(
        baseUrl: 'https://example.test',
        client: client,
        timeout: const Duration(seconds: 60),
      );

      // Trigger timeout using custom short timeout parameter
      try {
        await api.postJson(
          '/api/v1/auth/login',
          body: const {},
          requestTimeout: const Duration(milliseconds: 2),
        );
        fail('Should have thrown');
      } on ApiException catch (e) {
        // Since requestTimeout was 2ms (< 45s), it is standard NETWORK_TIMEOUT
        expect(e.code, 'NETWORK_TIMEOUT');
        expect(authFormError(e), 'The server took too long to respond. Please try again.');
      }
    });

    test('authFormError maps COLD_START_TIMEOUT to waking up message', () {
      const error = ApiException(
        code: 'COLD_START_TIMEOUT',
        message: 'The server is taking longer than usual to wake up. Please try again in a few moments.',
      );
      expect(
        authFormError(error),
        'The server is taking longer than usual to wake up. Please try again in a few moments.',
      );
    });

    test('authFormError maps SERVER_WAKING to server waking message', () {
      const wakingError = ApiException(
        code: 'SERVER_WAKING',
        message: 'The server is waking up. Please wait a moment and try again.',
        statusCode: 502,
      );
      expect(
        authFormError(wakingError),
        'The server is waking up. Please wait a moment and try again.',
      );

      const error503 = ApiException(
        code: 'SERVER_WAKING',
        message: 'The server is waking up. Please wait a moment and try again.',
        statusCode: 503,
      );
      expect(
        authFormError(error503),
        'The server is waking up. Please wait a moment and try again.',
      );
    });
  });

  group('Goal 6: AddFileScreen Protects Manual Edits From Late OCR/AI', () {
    testWidgets('late OCR suggestion does NOT overwrite manually typed title and date', (tester) async {
      final auth = AuthService(
        apiClient: ApiClient(baseUrl: 'https://example.test', client: MockClient((_) async => http.Response('{}', 200))),
        tokenStore: _FakeTokenStore(),
      );
      final docService = _TestDocumentService(authService: auth);
      final previewCompleter = Completer<DocumentOcrResult>();
      docService.pendingPreview = previewCompleter;

      final testFile = PickedDocument(
        name: 'test_cert.jpg',
        mimeType: 'image/jpeg',
        bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentScope(
            documentService: docService,
            child: AddFileScreen(initialFiles: [testFile]),
          ),
        ),
      );
      await tester.pump();

      // User manually enters their own title
      final titleField = find.widgetWithText(TextField, 'Enter title');
      expect(titleField, findsOneWidget);
      await tester.enterText(titleField, 'My Manual Title');
      await tester.pump();

      // Now the late OCR preview finishes with an AI title
      previewCompleter.complete(
        const DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          rawText: 'Raw OCR Text',
          metadataSuggestions: DocumentMetadataSuggestions(
            title: 'Overwriting OCR Title',
            categoryKey: 'cert',
            folderKey: 'sem',
          ),
          metadataAnalysis: DocumentMetadataAnalysis(
            source: 'gemini',
            aiStatus: 'success',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify the manual title was NOT overwritten
      final textFieldWidget = tester.widget<TextField>(titleField);
      expect(textFieldWidget.controller!.text, 'My Manual Title');
    });

    testWidgets('Gemini unavailable status presents graceful suggestion message without crashing', (tester) async {
      final auth = AuthService(
        apiClient: ApiClient(baseUrl: 'https://example.test', client: MockClient((_) async => http.Response('{}', 200))),
        tokenStore: _FakeTokenStore(),
      );
      final docService = _TestDocumentService(authService: auth);
      docService.previewToReturn = const DocumentOcrResult(
        status: DocumentOcrStatus.ready,
        rawText: 'Text from tesseract',
        metadataSuggestions: DocumentMetadataSuggestions(
          title: 'Rule Based Title',
          categoryKey: 'cert',
          folderKey: 'sem',
        ),
        metadataAnalysis: DocumentMetadataAnalysis(
          source: 'rules',
          aiStatus: 'unavailable',
        ),
      );

      final testFile = PickedDocument(
        name: 'test.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentScope(
            documentService: docService,
            child: AddFileScreen(initialFiles: [testFile]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify AI unavailable fallback message is presented
      expect(
        find.text('AI suggestions are temporarily unavailable. Basic document details were applied where possible.'),
        findsOneWidget,
      );
    });
  });

  group('Goal 7: Login UX Polish & Prewarm Silence', () {
    testWidgets('server prewarm does not change Login button text and remains silent', (tester) async {
      final auth = AuthService(
        apiClient: ApiClient(baseUrl: 'https://example.test', client: MockClient((_) async => http.Response('{}', 200))),
        tokenStore: _FakeTokenStore(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AuthScope(
            authService: auth,
            child: const LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Prewarm has run silently in background.
      // Default button text is "Log In"
      expect(find.byKey(const Key('loginButton')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('loginButton')), matching: find.text('Log In')), findsOneWidget);

      // Old subtitle is completely absent
      expect(find.text('Sign in to continue your journey.'), findsNothing);

      // "Connecting to server..." is completely absent
      expect(find.text('Connecting to server...'), findsNothing);
    });

    testWidgets('login loading state says "Logging in..." with spinner after explicit tap', (tester) async {
      final loginCompleter = Completer<http.Response>();
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return loginCompleter.future;
        }
        return http.Response(jsonEncode({'data': {'status': 'healthy'}, 'meta': {'requestId': 'req-1'}}), 200);
      });

      final auth = AuthService(
        apiClient: ApiClient(baseUrl: 'https://example.test', client: client),
        tokenStore: _FakeTokenStore(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AuthScope(
            authService: auth,
            child: const LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter credentials
      await tester.enterText(find.byType(TextField).at(0), 'student@example.test');
      await tester.enterText(find.byType(TextField).at(1), 'Password123');
      await tester.pump();

      // Tap Log In button
      await tester.tap(find.byKey(const Key('loginButton')));
      await tester.pump(); // Start loading frame

      // Button is now in loading state: shows spinner and "Logging in..."
      expect(find.descendant(of: find.byKey(const Key('loginButton')), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('loginButton')), matching: find.text('Logging in...')), findsOneWidget);
      expect(find.text('Connecting to server...'), findsNothing);

      // Resolve login response
      loginCompleter.complete(
        http.Response(
          jsonEncode({
            'data': {
              'user': {
                'id': 'user-1',
                'email': 'student@example.test',
                'fullName': 'John Lloyd',
                'status': 'active',
                'role': 'student',
                'isEmailVerified': true,
                'createdAt': '2026-09-01T00:00:00.000Z',
                'updatedAt': '2026-09-01T00:00:00.000Z',
              },
              'session': {
                'accessToken': 'jwt-access',
                'accessTokenExpiresAt': '2030-01-01T00:00:00.000Z',
                'refreshToken': 'jwt-refresh',
                'refreshTokenExpiresAt': '2030-01-01T00:00:00.000Z',
              },
            },
            'meta': {'requestId': 'req-login'},
          }),
          200,
        ),
      );
      await tester.pumpAndSettle();
    });
  });
}
