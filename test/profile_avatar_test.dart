import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proport_app/screens/profile/widgets/profile_avatar.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_models.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/secure_token_store.dart';

void main() {
  final sampleImageBytes = Uint8List.fromList([
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0A,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0x00,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);

  group('ProfileAvatar Widget', () {
    testWidgets('renders Image.memory when avatarBytes is provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatar(
              avatarBytes: sampleImageBytes,
              initials: 'JD',
              size: 100,
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('JD'), findsNothing);
      expect(find.byIcon(Icons.person_rounded), findsNothing);
    });

    testWidgets(
      'renders initials when avatarBytes is null and initials are provided',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ProfileAvatar(avatarBytes: null, initials: 'JL', size: 100),
            ),
          ),
        );

        expect(find.byType(Image), findsNothing);
        expect(find.text('JL'), findsOneWidget);
        expect(find.byIcon(Icons.person_rounded), findsNothing);
      },
    );

    testWidgets(
      'renders person icon when avatarBytes and initials are absent',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ProfileAvatar(avatarBytes: null, initials: null, size: 100),
            ),
          ),
        );

        expect(find.byType(Image), findsNothing);
        expect(find.byIcon(Icons.person_rounded), findsOneWidget);
      },
    );

    testWidgets('shows loading spinner when isLoading is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProfileAvatar(
              avatarBytes: null,
              initials: 'JL',
              isLoading: true,
              size: 100,
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('JL'), findsNothing);
    });

    testWidgets('shows edit camera badge when showEditBadge is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProfileAvatar(
              avatarBytes: null,
              initials: 'JL',
              showEditBadge: true,
              size: 100,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatar(
              avatarBytes: null,
              initials: 'JL',
              onTap: () => tapped = true,
              size: 100,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ProfileAvatar));
      expect(tapped, isTrue);
    });
  });

  group('AuthUser and UserProfile initials helper', () {
    test('computes initials correctly from names and emails', () {
      final user1 = AuthUser(
        id: '1',
        email: 'john@example.com',
        firstName: 'John',
        lastName: 'Lloyd',
        program: '',
        yearLevel: '',
        school: '',
        status: 'active',
        emailVerifiedAt: null,
      );
      expect(user1.initials, 'JL');

      final user2 = AuthUser(
        id: '2',
        email: 'single@example.com',
        firstName: 'Single',
        lastName: '',
        program: '',
        yearLevel: '',
        school: '',
        status: 'active',
        emailVerifiedAt: null,
      );
      expect(user2.initials, 'S');

      final user3 = AuthUser(
        id: '3',
        email: 'guest@example.com',
        firstName: '',
        lastName: '',
        program: '',
        yearLevel: '',
        school: '',
        status: 'active',
        emailVerifiedAt: null,
      );
      expect(user3.initials, 'G');
    });
  });

  group('AuthService avatar management', () {
    test('fetchAvatar returns bytes and sets avatarBytes property', () async {
      final auth = _createTestAuthService(
        onGetBytes: (path) async {
          if (path == '/api/v1/users/me/avatar') return sampleImageBytes;
          throw const ApiException(
            code: 'NOT_FOUND',
            message: 'Not found',
            statusCode: 404,
          );
        },
      );

      expect(auth.avatarBytes, isNull);
      final bytes = await auth.fetchAvatar();
      expect(bytes, equals(sampleImageBytes));
      expect(auth.avatarBytes, equals(sampleImageBytes));
      auth.dispose();
    });

    test(
      'fetchAvatar handles 404 by clearing avatarBytes and returning null',
      () async {
        final auth = _createTestAuthService(
          onGetBytes: (path) async {
            throw const ApiException(
              code: 'AVATAR_NOT_FOUND',
              message: 'No avatar',
              statusCode: 404,
            );
          },
        );

        final bytes = await auth.fetchAvatar();
        expect(bytes, isNull);
        expect(auth.avatarBytes, isNull);
        auth.dispose();
      },
    );

    test('updateAvatar sets avatarBytes and updates user', () async {
      final auth = _createTestAuthService(
        onPostMultipart: (path, fields, fileName, mimeType, fileBytes) async {
          expect(path, '/api/v1/users/me/avatar');
          expect(fileName, 'new_avatar.png');
          expect(mimeType, 'image/png');
          return {
            'data': {
              'user': {
                'id': 'user-123',
                'email': 'user@example.com',
                'firstName': 'User',
                'lastName': 'Test',
                'program': 'BSIT',
                'yearLevel': '4th',
                'school': 'NEU',
                'status': 'active',
                'emailVerifiedAt': null,
                'hasAvatar': true,
              },
            },
          };
        },
      );

      final updatedUser = await auth.updateAvatar(
        bytes: sampleImageBytes,
        filename: 'new_avatar.png',
        mimeType: 'image/png',
      );

      expect(updatedUser.hasAvatar, isTrue);
      expect(auth.avatarBytes, equals(sampleImageBytes));
      auth.dispose();
    });

    test('deleteAvatar resets avatarBytes and updates user', () async {
      final auth = _createTestAuthService(
        onDeleteJson: (path) async {
          expect(path, '/api/v1/users/me/avatar');
          return {
            'data': {
              'user': {
                'id': 'user-123',
                'email': 'user@example.com',
                'firstName': 'User',
                'lastName': 'Test',
                'program': 'BSIT',
                'yearLevel': '4th',
                'school': 'NEU',
                'status': 'active',
                'emailVerifiedAt': null,
                'hasAvatar': false,
              },
            },
          };
        },
      );

      final updatedUser = await auth.deleteAvatar();
      expect(updatedUser.hasAvatar, isFalse);
      expect(auth.avatarBytes, isNull);
      auth.dispose();
    });
  });
}

AuthService _createTestAuthService({
  Future<Uint8List> Function(String path)? onGetBytes,
  Future<Map<String, dynamic>> Function(
    String path,
    Map<String, String> fields,
    String fileName,
    String mimeType,
    Uint8List fileBytes,
  )?
  onPostMultipart,
  Future<Map<String, dynamic>> Function(String path)? onDeleteJson,
}) {
  return _TestAuthService(
    onGetBytes: onGetBytes,
    onPostMultipart: onPostMultipart,
    onDeleteJson: onDeleteJson,
  );
}

class _TestAuthService extends AuthService {
  _TestAuthService({this.onGetBytes, this.onPostMultipart, this.onDeleteJson})
    : super(
        apiClient: ApiClient(
          baseUrl: 'http://example.test:3000',
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'data': {
                  'user': {
                    'id': 'user-123',
                    'email': 'user@example.com',
                    'firstName': 'User',
                    'lastName': 'Test',
                    'program': 'BSIT',
                    'yearLevel': '4th',
                    'school': 'NEU',
                    'status': 'active',
                    'emailVerifiedAt': null,
                    'hasAvatar': false,
                  },
                  'tokens': {
                    'tokenType': 'Bearer',
                    'accessToken': 'test-access-token',
                    'accessTokenExpiresAt': DateTime.now()
                        .add(const Duration(hours: 1))
                        .toIso8601String(),
                    'refreshToken': 'test-refresh-token',
                    'refreshTokenExpiresAt': DateTime.now()
                        .add(const Duration(days: 7))
                        .toIso8601String(),
                  },
                },
                'meta': {'requestId': 'req-123'},
              }),
              200,
            ),
          ),
        ),
        tokenStore: _MemoryTokenStore(),
      );

  final Future<Uint8List> Function(String path)? onGetBytes;
  final Future<Map<String, dynamic>> Function(
    String path,
    Map<String, String> fields,
    String fileName,
    String mimeType,
    Uint8List fileBytes,
  )?
  onPostMultipart;
  final Future<Map<String, dynamic>> Function(String path)? onDeleteJson;

  @override
  Future<Uint8List> authenticatedGetBytes(
    String path, {
    Duration? requestTimeout,
  }) async {
    if (onGetBytes != null) return onGetBytes!(path);
    return super.authenticatedGetBytes(path, requestTimeout: requestTimeout);
  }

  @override
  Future<Map<String, dynamic>> authenticatedPostMultipart(
    String path, {
    required Map<String, String> fields,
    required String fileName,
    required String mimeType,
    required Uint8List fileBytes,
    Duration? requestTimeout,
  }) async {
    if (onPostMultipart != null) {
      return onPostMultipart!(path, fields, fileName, mimeType, fileBytes);
    }
    return super.authenticatedPostMultipart(
      path,
      fields: fields,
      fileName: fileName,
      mimeType: mimeType,
      fileBytes: fileBytes,
      requestTimeout: requestTimeout,
    );
  }

  @override
  Future<Map<String, dynamic>> authenticatedDeleteJson(String path) async {
    if (onDeleteJson != null) return onDeleteJson!(path);
    return super.authenticatedDeleteJson(path);
  }
}

class _MemoryTokenStore implements SecureTokenStore {
  String? _token = 'saved-refresh-token';

  @override
  Future<void> deleteRefreshToken() async => _token = null;

  @override
  Future<String?> readRefreshToken() async => _token;

  @override
  Future<void> writeRefreshToken(String refreshToken) async =>
      _token = refreshToken;
}
