import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/secure_token_store.dart';

void main() {
  test(
    'registration sends only backend fields and excludes confirmation',
    () async {
      late Map<String, dynamic> requestBody;
      final api = ApiClient(
        baseUrl: 'http://example.test:3000',
        client: MockClient((request) async {
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _jsonResponse({
            'data': {
              'user': _userJson(status: 'pendingVerification'),
              'verification': {
                'required': true,
                'codeExpiresAt': '2030-01-01T00:10:00.000Z',
                'resendAvailableAt': '2030-01-01T00:01:00.000Z',
              },
            },
            'meta': {'requestId': 'request-register'},
          }, statusCode: 201);
        }),
      );
      final auth = AuthService(apiClient: api, tokenStore: _MemoryTokenStore());

      await auth.register(
        firstName: 'Grad',
        lastName: 'Student',
        email: 'student@example.com',
        password: ' Password1 ',
      );

      expect(requestBody, {
        'firstName': 'Grad',
        'lastName': 'Student',
        'email': 'student@example.com',
        'password': ' Password1 ',
      });
      expect(requestBody, isNot(contains('confirmPassword')));
      auth.dispose();
    },
  );

  test(
    'login preserves password bytes and persists only the refresh token',
    () async {
      late Map<String, dynamic> requestBody;
      final api = ApiClient(
        baseUrl: 'http://example.test:3000',
        client: MockClient((request) async {
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _jsonResponse(_sessionEnvelope(refreshToken: 'refresh-one'));
        }),
      );
      final store = _MemoryTokenStore();
      final auth = AuthService(apiClient: api, tokenStore: store);

      await auth.login(email: 'student@example.com', password: ' Password1 ');

      expect(requestBody, {
        'email': 'student@example.com',
        'password': ' Password1 ',
      });
      expect(store.value, 'refresh-one');
      expect(store.writes, ['refresh-one']);
      expect(auth.accessToken, 'access-token');
      expect(auth.isAuthenticated, isTrue);
      auth.dispose();
    },
  );

  test(
    'login applies scoped loginTimeout of coldStartTolerant (60s) and overrides shorter default',
    () async {
      Duration? capturedTimeout;
      final api = _TimeoutCapturingApiClient(
        timeout: const Duration(milliseconds: 1),
        client: MockClient((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          return _jsonResponse(_sessionEnvelope(refreshToken: 'refresh-timeout'));
        }),
        onPostJson: (path, timeout) {
          if (path == '/api/v1/auth/login') {
            capturedTimeout = timeout;
          }
        },
      );
      final store = _MemoryTokenStore();
      final auth = AuthService(apiClient: api, tokenStore: store);

      expect(AuthService.loginTimeout, ApiTimeoutPolicy.coldStartTolerant);

      final user = await auth.login(
        email: 'student@example.com',
        password: 'Password1',
      );

      expect(user.email, 'student@example.com');
      expect(capturedTimeout, AuthService.loginTimeout);
      expect(auth.isAuthenticated, isTrue);
      auth.dispose();
    },
  );

  test('EMAIL_NOT_VERIFIED does not trigger an automatic resend', () async {
    final requestedPaths = <String>[];
    final api = ApiClient(
      baseUrl: 'http://example.test:3000',
      client: MockClient((request) async {
        requestedPaths.add(request.url.path);
        return _jsonResponse({
          'error': {
            'code': 'EMAIL_NOT_VERIFIED',
            'message': 'Verify your email before logging in.',
            'requestId': 'request-1',
          },
        }, statusCode: 403);
      }),
    );
    final store = _MemoryTokenStore();
    final auth = AuthService(apiClient: api, tokenStore: store);

    await expectLater(
      auth.login(email: 'student@example.com', password: 'Password1'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'EMAIL_NOT_VERIFIED',
        ),
      ),
    );

    expect(requestedPaths, ['/api/v1/auth/login']);
    expect(store.writes, isEmpty);
    auth.dispose();
  });

  test(
    'email verification resend occurs only when explicitly requested',
    () async {
      final requestedPaths = <String>[];
      late Map<String, dynamic> requestBody;
      final api = ApiClient(
        baseUrl: 'http://example.test:3000',
        client: MockClient((request) async {
          requestedPaths.add(request.url.path);
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _jsonResponse({
            'data': {'status': 'verificationSent'},
            'meta': {'requestId': 'request-resend'},
          }, statusCode: 202);
        }),
      );
      final auth = AuthService(apiClient: api, tokenStore: _MemoryTokenStore());

      expect(requestedPaths, isEmpty);
      await auth.resendEmailVerification(email: 'student@example.com');

      expect(requestedPaths, ['/api/v1/auth/email-verification/resend']);
      expect(requestBody, {'email': 'student@example.com'});
      auth.dispose();
    },
  );

  test(
    'session restoration rotates and replaces the stored refresh token',
    () async {
      late Map<String, dynamic> requestBody;
      final api = ApiClient(
        baseUrl: 'http://example.test:3000',
        client: MockClient((request) async {
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _jsonResponse(_sessionEnvelope(refreshToken: 'refresh-new'));
        }),
      );
      final store = _MemoryTokenStore('refresh-old');
      final auth = AuthService(apiClient: api, tokenStore: store);

      final result = await auth.restoreSession();

      expect(result, SessionRestoreResult.authenticated);
      expect(requestBody, {'refreshToken': 'refresh-old'});
      expect(store.value, 'refresh-new');
      expect(store.writes, ['refresh-new']);
      auth.dispose();
    },
  );

  test('invalid refresh clears secure storage', () async {
    final api = ApiClient(
      baseUrl: 'http://example.test:3000',
      client: MockClient((_) async {
        return _jsonResponse({
          'error': {
            'code': 'INVALID_REFRESH_TOKEN',
            'message': 'Your session has expired.',
            'requestId': 'request-2',
          },
        }, statusCode: 401);
      }),
    );
    final store = _MemoryTokenStore('invalid-refresh');
    final auth = AuthService(apiClient: api, tokenStore: store);

    final result = await auth.restoreSession();

    expect(result, SessionRestoreResult.noSession);
    expect(store.value, isNull);
    expect(store.deleteCount, 1);
    auth.dispose();
  });

  test(
    'transient restore failure preserves the stored refresh token',
    () async {
      final api = ApiClient(
        baseUrl: 'http://example.test:3000',
        client: MockClient((_) async {
          return _jsonResponse({
            'error': {
              'code': 'AUTH_UNAVAILABLE',
              'message': 'Authentication is temporarily unavailable.',
              'requestId': 'request-5',
            },
          }, statusCode: 503);
        }),
      );
      final store = _MemoryTokenStore('still-valid-refresh');
      final auth = AuthService(apiClient: api, tokenStore: store);

      final result = await auth.restoreSession();

      expect(result, SessionRestoreResult.unavailable);
      expect(store.value, 'still-valid-refresh');
      expect(store.deleteCount, 0);
      auth.dispose();
    },
  );

  test(
    'logout clears local credentials even when revocation is offline',
    () async {
      final api = ApiClient(
        baseUrl: 'http://example.test:3000',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login')) {
            return _jsonResponse(_sessionEnvelope(refreshToken: 'refresh-one'));
          }
          throw http.ClientException('offline');
        }),
      );
      final store = _MemoryTokenStore();
      final auth = AuthService(apiClient: api, tokenStore: store);
      await auth.login(email: 'student@example.com', password: 'Password1');

      await expectLater(auth.logout(), throwsA(isA<ApiException>()));

      expect(store.value, isNull);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.accessToken, isNull);
      auth.dispose();
    },
  );

  test(
    'reset grant stays in memory and is sent only to reset completion',
    () async {
      final requestBodies = <String, Map<String, dynamic>>{};
      final api = ApiClient(
        baseUrl: 'http://example.test:3000',
        client: MockClient((request) async {
          requestBodies[request.url.path] =
              jsonDecode(request.body) as Map<String, dynamic>;
          if (request.url.path.endsWith('/verify')) {
            return _jsonResponse({
              'data': {
                'resetToken': 'memory-only-reset-grant',
                'resetTokenExpiresAt': '2030-01-01T00:10:00.000Z',
              },
              'meta': {'requestId': 'request-3'},
            });
          }
          return _jsonResponse({
            'data': {'status': 'passwordReset'},
            'meta': {'requestId': 'request-4'},
          });
        }),
      );
      final store = _MemoryTokenStore();
      final auth = AuthService(apiClient: api, tokenStore: store);

      final grant = await auth.verifyPasswordReset(
        email: 'student@example.com',
        code: '123456',
      );
      await auth.completePasswordReset(
        resetToken: grant,
        newPassword: 'NewPassword1',
      );

      expect(grant, 'memory-only-reset-grant');
      expect(store.writes, isEmpty);
      expect(requestBodies['/api/v1/auth/password-reset/verify'], {
        'email': 'student@example.com',
        'code': '123456',
      });
      expect(requestBodies['/api/v1/auth/password-reset/complete'], {
        'resetToken': 'memory-only-reset-grant',
        'newPassword': 'NewPassword1',
      });
      auth.dispose();
    },
  );

  test('current-user profile loads with the in-memory access token', () async {
    late http.Request profileRequest;
    final api = ApiClient(
      baseUrl: 'http://example.test:3000',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return _jsonResponse(_sessionEnvelope(refreshToken: 'refresh-one'));
        }
        profileRequest = request;
        return _jsonResponse({
          'data': {
            'user': _userJson(
              status: 'active',
              firstName: 'Loaded',
              program: 'Computer Science',
            ),
          },
          'meta': {'requestId': 'request-profile'},
        });
      }),
    );
    final auth = AuthService(apiClient: api, tokenStore: _MemoryTokenStore());
    await auth.login(email: 'student@example.com', password: 'Password1');

    final user = await auth.fetchCurrentUser();

    expect(profileRequest.method, 'GET');
    expect(profileRequest.url.path, '/api/v1/users/me');
    expect(profileRequest.headers['authorization'], 'Bearer access-token');
    expect(user.firstName, 'Loaded');
    expect(auth.user, same(user));
    auth.dispose();
  });

  test('profile update sends only allowed fields and updates memory', () async {
    late Map<String, dynamic> profileBody;
    final api = ApiClient(
      baseUrl: 'http://example.test:3000',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return _jsonResponse(_sessionEnvelope(refreshToken: 'refresh-one'));
        }
        profileBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _jsonResponse({
          'data': {
            'user': _userJson(
              status: 'active',
              firstName: 'Updated',
              lastName: 'Learner',
              program: 'Information Technology',
              yearLevel: '3rd Year',
              school: 'New Era University',
            ),
          },
          'meta': {'requestId': 'request-profile-update'},
        });
      }),
    );
    final auth = AuthService(apiClient: api, tokenStore: _MemoryTokenStore());
    await auth.login(email: 'student@example.com', password: 'Password1');

    final user = await auth.updateCurrentUserProfile(
      firstName: 'Updated',
      lastName: 'Learner',
      program: 'Information Technology',
      yearLevel: '3rd Year',
      school: 'New Era University',
    );

    expect(profileBody, {
      'firstName': 'Updated',
      'lastName': 'Learner',
      'program': 'Information Technology',
      'yearLevel': '3rd Year',
      'school': 'New Era University',
    });
    expect(profileBody, isNot(contains('id')));
    expect(profileBody, isNot(contains('email')));
    expect(user.program, 'Information Technology');
    expect(auth.user, same(user));
    auth.dispose();
  });

  test('authenticated profile requests refresh once after a 401', () async {
    var profileAttempts = 0;
    final store = _MemoryTokenStore();
    final api = ApiClient(
      baseUrl: 'http://example.test:3000',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return _jsonResponse(
            _sessionEnvelope(
              refreshToken: 'refresh-one',
              accessToken: 'access-one',
            ),
          );
        }
        if (request.url.path.endsWith('/refresh')) {
          expect(jsonDecode(request.body), {'refreshToken': 'refresh-one'});
          return _jsonResponse(
            _sessionEnvelope(
              refreshToken: 'refresh-two',
              accessToken: 'access-two',
            ),
          );
        }

        profileAttempts++;
        if (profileAttempts == 1) {
          expect(request.headers['authorization'], 'Bearer access-one');
          return _jsonResponse({
            'error': {
              'code': 'UNAUTHORIZED',
              'message': 'Authentication is required.',
              'requestId': 'request-rejected',
            },
          }, statusCode: 401);
        }
        expect(request.headers['authorization'], 'Bearer access-two');
        return _jsonResponse({
          'data': {'user': _userJson(status: 'active')},
          'meta': {'requestId': 'request-retry'},
        });
      }),
    );
    final auth = AuthService(apiClient: api, tokenStore: store);
    await auth.login(email: 'student@example.com', password: 'Password1');

    await auth.fetchCurrentUser();

    expect(profileAttempts, 2);
    expect(auth.accessToken, 'access-two');
    expect(store.value, 'refresh-two');
    auth.dispose();
  });

  test('authenticated document upload refreshes once after a 401', () async {
    var uploadAttempts = 0;
    final uploadTokens = <String?>[];
    final store = _MemoryTokenStore();
    final api = ApiClient(
      baseUrl: 'http://example.test:3000',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return _jsonResponse(
            _sessionEnvelope(
              refreshToken: 'refresh-one',
              accessToken: 'access-one',
            ),
          );
        }
        if (request.url.path.endsWith('/refresh')) {
          expect(jsonDecode(request.body), {'refreshToken': 'refresh-one'});
          return _jsonResponse(
            _sessionEnvelope(
              refreshToken: 'refresh-two',
              accessToken: 'access-two',
            ),
          );
        }

        uploadAttempts++;
        uploadTokens.add(request.headers['authorization']);
        if (uploadAttempts == 1) {
          return _jsonResponse({
            'error': {
              'code': 'UNAUTHORIZED',
              'message': 'Authentication is required.',
              'requestId': 'document-upload-rejected',
            },
          }, statusCode: 401);
        }
        expect(request.body, contains('%PDF-GradPort'));
        return _jsonResponse({
          'data': {
            'document': {'id': 'document-1'},
          },
          'meta': {'requestId': 'document-upload-retry'},
        }, statusCode: 201);
      }),
    );
    final auth = AuthService(apiClient: api, tokenStore: store);
    await auth.login(email: 'student@example.com', password: 'Password1');

    await auth.authenticatedPostMultipart(
      '/api/v1/documents',
      fields: const {
        'categoryKey': 'certificates',
        'folderKey': 'seminars',
        'title': 'Certificate',
        'documentDate': '2026-09-11',
      },
      fileName: 'certificate.pdf',
      mimeType: 'application/pdf',
      fileBytes: Uint8List.fromList('%PDF-GradPort'.codeUnits),
    );

    expect(uploadAttempts, 2);
    expect(uploadTokens, ['Bearer access-one', 'Bearer access-two']);
    expect(auth.accessToken, 'access-two');
    expect(store.value, 'refresh-two');
    auth.dispose();
  });

  test(
    'invalid refresh after profile authentication failure clears storage',
    () async {
      final store = _MemoryTokenStore();
      final api = ApiClient(
        baseUrl: 'http://example.test:3000',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login')) {
            return _jsonResponse(_sessionEnvelope(refreshToken: 'refresh-one'));
          }
          if (request.url.path.endsWith('/refresh')) {
            return _jsonResponse({
              'error': {
                'code': 'INVALID_REFRESH_TOKEN',
                'message': 'The refresh token is invalid or has expired.',
                'requestId': 'request-refresh-rejected',
              },
            }, statusCode: 401);
          }
          return _jsonResponse({
            'error': {
              'code': 'UNAUTHORIZED',
              'message': 'Authentication is required.',
              'requestId': 'request-profile-rejected',
            },
          }, statusCode: 401);
        }),
      );
      final auth = AuthService(apiClient: api, tokenStore: store);
      await auth.login(email: 'student@example.com', password: 'Password1');

      await expectLater(
        auth.fetchCurrentUser(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'INVALID_REFRESH_TOKEN',
          ),
        ),
      );

      expect(store.value, isNull);
      expect(auth.isAuthenticated, isFalse);
      auth.dispose();
    },
  );
}

class _MemoryTokenStore implements SecureTokenStore {
  _MemoryTokenStore([this.value]);

  String? value;
  final writes = <String>[];
  int deleteCount = 0;

  @override
  Future<void> deleteRefreshToken() async {
    deleteCount++;
    value = null;
  }

  @override
  Future<String?> readRefreshToken() async => value;

  @override
  Future<void> writeRefreshToken(String refreshToken) async {
    writes.add(refreshToken);
    value = refreshToken;
  }
}

class _TimeoutCapturingApiClient extends ApiClient {
  _TimeoutCapturingApiClient({
    required super.client,
    super.timeout,
    this.onPostJson,
  }) : super(baseUrl: 'http://example.test:3000');

  final void Function(String path, Duration? requestTimeout)? onPostJson;
  Duration? lastPostJsonTimeout;

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    required Map<String, dynamic> body,
    String? bearerToken,
    Duration? requestTimeout,
  }) {
    lastPostJsonTimeout = requestTimeout;
    onPostJson?.call(path, requestTimeout);
    return super.postJson(
      path,
      body: body,
      bearerToken: bearerToken,
      requestTimeout: requestTimeout,
    );
  }
}

http.Response _jsonResponse(Map<String, dynamic> body, {int statusCode = 200}) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

Map<String, dynamic> _sessionEnvelope({
  required String refreshToken,
  String accessToken = 'access-token',
}) {
  return {
    'data': {
      'user': _userJson(status: 'active'),
      'tokens': {
        'tokenType': 'Bearer',
        'accessToken': accessToken,
        'accessTokenExpiresAt': '2030-01-01T00:15:00.000Z',
        'refreshToken': refreshToken,
        'refreshTokenExpiresAt': '2030-01-31T00:00:00.000Z',
      },
    },
    'meta': {'requestId': 'request-session'},
  };
}

Map<String, dynamic> _userJson({
  required String status,
  String firstName = 'Grad',
  String lastName = 'Student',
  String program = '',
  String yearLevel = '',
  String school = '',
}) {
  return {
    'id': 'user-1',
    'email': 'student@example.com',
    'firstName': firstName,
    'lastName': lastName,
    'program': program,
    'yearLevel': yearLevel,
    'school': school,
    'status': status,
    'emailVerifiedAt': status == 'active' ? '2030-01-01T00:00:00.000Z' : null,
  };
}
