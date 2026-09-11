import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proport_app/screens/portfolio/models/portfolio_models.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/portfolio_service.dart';
import 'package:proport_app/services/secure_token_store.dart';

void main() {
  test(
    'loads and preserves safe ownerless portfolio request payloads',
    () async {
      final requests = <http.Request>[];
      final api = ApiClient(
        baseUrl: 'http://example.test:3000',
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/login')) {
            return _response(_sessionEnvelope());
          }
          if (request.method == 'GET') {
            return _response({
              'data': {
                'portfolios': [_portfolioJson(id: 'portfolio-1')],
              },
              'meta': {'requestId': 'list'},
            });
          }
          if (request.method == 'POST') {
            return _response({
              'data': {'portfolio': _portfolioJson(id: 'portfolio-2')},
              'meta': {'requestId': 'create'},
            }, statusCode: 201);
          }
          if (request.method == 'PATCH') {
            return _response({
              'data': {
                'portfolio': _portfolioJson(
                  id: 'portfolio-2',
                  course: 'Updated Course',
                ),
              },
              'meta': {'requestId': 'update'},
            });
          }
          return _response({
            'data': {'status': 'deleted', 'portfolioId': 'portfolio-2'},
            'meta': {'requestId': 'delete'},
          });
        }),
      );
      final auth = AuthService(apiClient: api, tokenStore: _MemoryTokenStore());
      await auth.login(email: 'student@example.edu', password: 'Password8');
      final portfolios = PortfolioService(authService: auth);

      await portfolios.loadPortfolios();
      expect(portfolios.portfolios.map((item) => item.id), ['portfolio-1']);

      final info = _info(course: 'Original Course');
      await portfolios.createPortfolio(info);
      expect(portfolios.portfolios.first.id, 'portfolio-2');
      await portfolios.updatePortfolio('portfolio-2', info);
      expect(portfolios.portfolios.first.info.course, 'Updated Course');
      await portfolios.deletePortfolio('portfolio-2');
      expect(portfolios.portfolios.map((item) => item.id), ['portfolio-1']);

      final authenticated = requests.where(
        (request) => !request.url.path.endsWith('/login'),
      );
      expect(
        authenticated.every(
          (request) => request.headers['authorization'] == 'Bearer access-1',
        ),
        isTrue,
      );
      for (final request in authenticated.where(
        (request) => request.body.isNotEmpty,
      )) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body, isNot(contains('ownerId')));
        expect(body, isNot(contains('userId')));
      }

      portfolios.dispose();
      auth.dispose();
    },
  );

  test(
    'retries a portfolio load through the existing refresh rotation',
    () async {
      var listAttempts = 0;
      final store = _MemoryTokenStore();
      final api = ApiClient(
        baseUrl: 'http://example.test:3000',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login')) {
            return _response(_sessionEnvelope());
          }
          if (request.url.path.endsWith('/refresh')) {
            expect(jsonDecode(request.body), {'refreshToken': 'refresh-1'});
            return _response(
              _sessionEnvelope(
                accessToken: 'access-2',
                refreshToken: 'refresh-2',
              ),
            );
          }
          listAttempts++;
          if (listAttempts == 1) {
            expect(request.headers['authorization'], 'Bearer access-1');
            return _response({
              'error': {
                'code': 'UNAUTHORIZED',
                'message': 'Authentication is required.',
                'requestId': 'denied',
              },
            }, statusCode: 401);
          }
          expect(request.headers['authorization'], 'Bearer access-2');
          return _response({
            'data': {'portfolios': <Object>[]},
            'meta': {'requestId': 'list'},
          });
        }),
      );
      final auth = AuthService(apiClient: api, tokenStore: store);
      await auth.login(email: 'student@example.edu', password: 'Password8');
      final portfolios = PortfolioService(authService: auth);

      await portfolios.loadPortfolios();

      expect(listAttempts, 2);
      expect(store.value, 'refresh-2');
      expect(portfolios.portfolios, isEmpty);
      portfolios.dispose();
      auth.dispose();
    },
  );

  test(
    'surfaces structured API errors and clears cached data on logout',
    () async {
      var failLoad = false;
      final api = ApiClient(
        baseUrl: 'http://example.test:3000',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login')) {
            return _response(_sessionEnvelope());
          }
          if (request.url.path.endsWith('/logout')) {
            return _response({
              'data': {'status': 'loggedOut'},
              'meta': {'requestId': 'logout'},
            });
          }
          if (failLoad) {
            return _response({
              'error': {
                'code': 'PORTFOLIO_UNAVAILABLE',
                'message': 'Portfolios are temporarily unavailable.',
                'requestId': 'failed-list',
              },
            }, statusCode: 503);
          }
          return _response({
            'data': {
              'portfolios': [_portfolioJson(id: 'portfolio-1')],
            },
            'meta': {'requestId': 'list'},
          });
        }),
      );
      final auth = AuthService(apiClient: api, tokenStore: _MemoryTokenStore());
      await auth.login(email: 'student@example.edu', password: 'Password8');
      final portfolios = PortfolioService(authService: auth);
      await portfolios.loadPortfolios();
      expect(portfolios.portfolios, hasLength(1));

      failLoad = true;
      await expectLater(
        portfolios.loadPortfolios(force: true),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'PORTFOLIO_UNAVAILABLE',
          ),
        ),
      );
      expect(portfolios.portfolios, hasLength(1));

      await auth.logout();
      expect(portfolios.portfolios, isEmpty);
      expect(portfolios.hasLoaded, isFalse);
      portfolios.dispose();
      auth.dispose();
    },
  );
}

class _MemoryTokenStore implements SecureTokenStore {
  String? value;

  @override
  Future<void> deleteRefreshToken() async => value = null;

  @override
  Future<String?> readRefreshToken() async => value;

  @override
  Future<void> writeRefreshToken(String refreshToken) async =>
      value = refreshToken;
}

PortfolioInfo _info({String course = 'Free Elective'}) => PortfolioInfo(
  fullName: 'Portfolio Student',
  yearAndSection: '4BSIT-1',
  schedule: 'Monday 8:00 AM',
  instructorName: 'Professor Example',
  course: course,
  courseCode: 'CCSFE4-18',
  semesterAndYear: '2nd Semester, A.Y. 2025-2026',
);

Map<String, dynamic> _portfolioJson({
  required String id,
  String course = 'Free Elective',
}) => {
  'id': id,
  ..._info(course: course).toMap(),
  'createdAt': '2026-09-01T00:00:00.000Z',
  'updatedAt': course == 'Updated Course'
      ? '2026-09-02T00:00:00.000Z'
      : '2026-09-01T00:00:00.000Z',
};

Map<String, dynamic> _sessionEnvelope({
  String accessToken = 'access-1',
  String refreshToken = 'refresh-1',
}) => {
  'data': {
    'user': {
      'id': 'user-1',
      'email': 'student@example.edu',
      'firstName': 'Portfolio',
      'lastName': 'Student',
      'program': '',
      'yearLevel': '',
      'school': '',
      'status': 'active',
      'emailVerifiedAt': '2026-09-01T00:00:00.000Z',
    },
    'tokens': {
      'tokenType': 'Bearer',
      'accessToken': accessToken,
      'accessTokenExpiresAt': '2030-01-01T00:15:00.000Z',
      'refreshToken': refreshToken,
      'refreshTokenExpiresAt': '2030-01-31T00:00:00.000Z',
    },
  },
  'meta': {'requestId': 'login'},
};

http.Response _response(Map<String, dynamic> body, {int statusCode = 200}) =>
    http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
