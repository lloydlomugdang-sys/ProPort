import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/screens/portfolio/portfolio_list_screen.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/portfolio_scope.dart';
import 'package:proport_app/services/portfolio_service.dart';
import 'package:proport_app/services/secure_token_store.dart';

void main() {
  testWidgets('shows loading then an honest empty portfolio state', (
    tester,
  ) async {
    final auth = _FakePortfolioAuthService();
    auth.pendingList = Completer<Map<String, dynamic>>();
    final service = PortfolioService(authService: auth);
    addTearDown(() {
      service.dispose();
      auth.dispose();
    });

    await tester.pumpWidget(_app(service));
    await tester.pump();
    expect(find.byKey(const Key('portfolio-loading')), findsOneWidget);

    auth.pendingList!.complete(_envelope({'portfolios': <Object>[]}));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('portfolio-empty')), findsOneWidget);
    expect(find.text('No portfolios yet.'), findsOneWidget);
    expect(find.text('John Dela Cruz'), findsNothing);
  });

  testWidgets('loads, views, and edits a persisted portfolio immediately', (
    tester,
  ) async {
    final auth = _FakePortfolioAuthService([
      _portfolioJson(id: 'portfolio-1', course: 'Original Course'),
    ]);
    final service = PortfolioService(authService: auth);
    addTearDown(() {
      service.dispose();
      auth.dispose();
    });

    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();

    expect(find.text('Portfolio Student'), findsOneWidget);
    expect(find.textContaining('Original Course'), findsOneWidget);
    expect(find.text('Monday 8:00 AM - 10:00 AM'), findsOneWidget);

    await tester.tap(find.byKey(const Key('view-portfolio-1')));
    await tester.pumpAndSettle();
    expect(auth.itemGetCount, 1);
    expect(find.text('Portfolio Preview'), findsOneWidget);
    expect(find.text('Portfolio Student'), findsWidgets);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('edit-portfolio-1')));
    await tester.pumpAndSettle();
    expect(find.text('Edit Portfolio'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(4), 'Updated Course');
    final saveButton = find.text('Save Changes');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(auth.patchCount, 1);
    expect(find.textContaining('Updated Course'), findsOneWidget);
    expect(find.text('Portfolio updated successfully.'), findsOneWidget);
  });

  testWidgets(
    'creates and deletes a portfolio through the existing form flow',
    (tester) async {
      final auth = _FakePortfolioAuthService();
      final service = PortfolioService(authService: auth);
      addTearDown(() {
        service.dispose();
        auth.dispose();
      });

      await tester.pumpWidget(_app(service));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create Portfolio'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'New Portfolio Student');
      await tester.enterText(fields.at(1), '3BSIT-2');
      await tester.enterText(fields.at(2), 'Professor New');
      await tester.enterText(fields.at(3), 'Mobile Development');

      await tester.ensureVisible(find.byKey(const Key('schedule-day')));
      await tester.tap(find.byKey(const Key('schedule-day')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Friday').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('schedule-start-time')));
      await tester.tap(find.byKey(const Key('schedule-start-time')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('schedule-end-time')));
      await tester.tap(find.byKey(const Key('schedule-end-time')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final nextButton = find.text('Save Portfolio');
      await tester.ensureVisible(nextButton);
      await tester.tap(nextButton);
      await tester.pumpAndSettle();

      expect(auth.postCount, 1);
      expect(find.text('Portfolio Saved'), findsOneWidget);
      expect(find.text('Saved to My Portfolios'), findsOneWidget);
      expect(
        find.text('PDF/DOCX export is not available yet.'),
        findsOneWidget,
      );
      expect(find.text('Friday 8:00 AM - 9:00 AM'), findsOneWidget);
      await tester.tap(find.text('View Portfolio'));
      await tester.pumpAndSettle();
      expect(auth.itemGetCount, 1);
      expect(find.text('Portfolio Preview'), findsOneWidget);
      expect(find.text('Confirm & Export'), findsNothing);
      expect(find.text('Portfolio Exported'), findsNothing);
      await tester.tap(find.text('Back to My Portfolios'));
      await tester.pumpAndSettle();

      expect(find.text('My Portfolios'), findsOneWidget);
      expect(find.text('Portfolio Preview'), findsNothing);
      expect(find.text('New Portfolio Student'), findsOneWidget);
      expect(find.text('Friday 8:00 AM - 9:00 AM'), findsOneWidget);
      // A new service instance restores the same server record after restart.
      await tester.pumpWidget(const SizedBox.shrink());
      final restored = PortfolioService(authService: auth);
      await tester.pumpWidget(_app(restored));
      await tester.pumpAndSettle();
      expect(restored.portfolios.single.id, 'portfolio-1');
      await restored.loadPortfolios(force: true);
      await tester.pumpAndSettle();
      expect(restored.portfolios, hasLength(1));
      await tester.tap(find.byKey(const Key('view-portfolio-1')));
      await tester.pumpAndSettle();
      expect(find.text('Portfolio Preview'), findsOneWidget);
      await tester.tap(find.text('Back to My Portfolios'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete-portfolio-1')));
      await tester.pumpAndSettle();
      expect(find.text('Delete Portfolio'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(auth.deleteCount, 1);
      expect(find.byKey(const Key('portfolio-empty')), findsOneWidget);
      expect(find.text('Portfolio deleted successfully.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      restored.dispose();
    },
  );

  testWidgets('shows a safe API error when loading fails', (tester) async {
    final auth = _FakePortfolioAuthService()..failList = true;
    final service = PortfolioService(authService: auth);
    addTearDown(() {
      service.dispose();
      auth.dispose();
    });

    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('portfolio-error')), findsOneWidget);
    expect(find.text('Portfolio service is unavailable.'), findsOneWidget);
  });
}

Widget _app(PortfolioService service) => PortfolioScope(
  portfolioService: service,
  child: const MaterialApp(home: PortfolioListScreen()),
);

class _FakePortfolioAuthService extends AuthService {
  _FakePortfolioAuthService([List<Map<String, dynamic>> initial = const []])
    : serverPortfolios = initial.map(Map<String, dynamic>.from).toList(),
      super(tokenStore: _EmptyTokenStore());

  final List<Map<String, dynamic>> serverPortfolios;
  Completer<Map<String, dynamic>>? pendingList;
  bool failList = false;
  int itemGetCount = 0;
  int postCount = 0;
  int patchCount = 0;
  int deleteCount = 0;

  @override
  Future<Map<String, dynamic>> authenticatedGetJson(String path) async {
    if (path == '/api/v1/portfolios') {
      if (pendingList != null) return pendingList!.future;
      if (failList) {
        throw const ApiException(
          code: 'PORTFOLIO_UNAVAILABLE',
          message: 'Portfolio service is unavailable.',
          statusCode: 503,
        );
      }
      return _envelope({'portfolios': serverPortfolios});
    }
    itemGetCount++;
    final id = path.split('/').last;
    return _envelope({
      'portfolio': serverPortfolios.singleWhere(
        (portfolio) => portfolio['id'] == id,
      ),
    });
  }

  @override
  Future<Map<String, dynamic>> authenticatedPostJson(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    postCount++;
    expect(path, '/api/v1/portfolios');
    expect(body, isNot(contains('ownerId')));
    final portfolio = {
      'id': 'portfolio-${serverPortfolios.length + 1}',
      ...body,
      'createdAt': '2026-09-01T00:00:00.000Z',
      'updatedAt': '2026-09-01T00:00:00.000Z',
    };
    serverPortfolios.insert(0, portfolio);
    return _envelope({'portfolio': portfolio});
  }

  @override
  Future<Map<String, dynamic>> authenticatedPatchJson(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    patchCount++;
    expect(body, isNot(contains('ownerId')));
    final id = path.split('/').last;
    final index = serverPortfolios.indexWhere(
      (portfolio) => portfolio['id'] == id,
    );
    final updated = {
      ...serverPortfolios[index],
      ...body,
      'updatedAt': '2026-09-02T00:00:00.000Z',
    };
    serverPortfolios[index] = updated;
    return _envelope({'portfolio': updated});
  }

  @override
  Future<Map<String, dynamic>> authenticatedDeleteJson(String path) async {
    deleteCount++;
    final id = path.split('/').last;
    serverPortfolios.removeWhere((portfolio) => portfolio['id'] == id);
    return _envelope({'status': 'deleted', 'portfolioId': id});
  }
}

class _EmptyTokenStore implements SecureTokenStore {
  @override
  Future<void> deleteRefreshToken() async {}

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> writeRefreshToken(String refreshToken) async {}
}

Map<String, dynamic> _portfolioJson({
  required String id,
  required String course,
}) => {
  'id': id,
  'fullName': 'Portfolio Student',
  'yearAndSection': '4BSIT-1',
  'schedule': 'Monday 8:00 AM - 10:00 AM',
  'instructorName': 'Professor Example',
  'course': course,
  'courseCode': 'CCSFE4-18',
  'semesterAndYear': '2nd Semester, A.Y. 2025-2026',
  'createdAt': '2026-09-01T00:00:00.000Z',
  'updatedAt': '2026-09-01T00:00:00.000Z',
};

Map<String, dynamic> _envelope(Map<String, dynamic> data) => {
  'data': data,
  'meta': {'requestId': 'portfolio-widget-test'},
};
