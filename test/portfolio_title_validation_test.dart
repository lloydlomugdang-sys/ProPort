import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/screens/portfolio/models/portfolio_models.dart';
import 'package:proport_app/screens/portfolio/portfolio_info_screen.dart';
import 'package:proport_app/screens/portfolio/widgets/portfolio_text_field.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/portfolio_export_service.dart';
import 'package:proport_app/services/portfolio_scope.dart';
import 'package:proport_app/services/portfolio_service.dart';

const _valid = PortfolioInfo(
  fullName: 'Real Student',
  yearAndSection: '4-A',
  schedule: 'Monday 8:00 AM - 10:00 AM',
  instructorName: 'Real Instructor',
  course: 'Computer Science',
  courseCode: 'CS401',
  semesterAndYear: 'First semester 2026-2027',
);

class _Auth extends AuthService {
  int writes = 0;
  Map<String, dynamic>? submitted;
  @override
  Future<Map<String, dynamic>> authenticatedPatchJson(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    writes++;
    submitted = body;
    return {
      'data': {
        'portfolio': {
          ...body,
          'id': 'saved',
          'createdAt': '2026-01-01T00:00:00Z',
          'updatedAt': '2026-01-01T00:00:00Z',
        },
      },
    };
  }
}

Finder _field(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is PortfolioTextField && widget.label == label,
  ),
  matching: find.byType(TextField),
);

void main() {
  for (final key in PortfolioInfo.fieldLabels.keys) {
    for (final invalid in [
      '',
      ' \t\n ',
      'x' * (PortfolioInfo.fieldLimits[key]! + 1),
    ]) {
      test('title rejects $key (${invalid.length} characters)', () {
        final info = PortfolioInfo.fromJson({..._valid.toMap(), key: invalid});
        expect(info.validationErrors.keys, [key]);
      });
    }
  }

  test('service boundary blocks invalid title before any request', () async {
    final auth = _Auth();
    final service = PortfolioService(authService: auth);
    await expectLater(
      service.updatePortfolio('saved', _valid.copyWith(course: '  ')),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'VALIDATION_ERROR',
        ),
      ),
    );
    expect(auth.writes, 0);
    service.dispose();
    auth.dispose();
  });

  test('device generation blocks incomplete legacy title pages', () async {
    await expectLater(
      const DevicePortfolioExporter().generate(
        const PortfolioExportContent(
          titleFields: {'Full Name': 'Student'},
          sections: [],
          totalDocuments: 0,
        ),
        ExportFormat.pdf,
      ),
      throwsA(
        isA<PortfolioExportException>().having(
          (error) => error.message,
          'message',
          contains('edit the portfolio title page'),
        ),
      ),
    );
  });

  for (final input in [
    ('Full Name', ''),
    ('Course', '   '),
    ("Instructor's Name", 'x' * 201),
  ]) {
    testWidgets(
      'inline ${input.$1} error blocks saving, preserves other facts, and focuses it',
      (tester) async {
        final auth = _Auth();
        final service = PortfolioService(authService: auth);
        await _open(tester, service);
        await tester.ensureVisible(_field(input.$1));
        await tester.enterText(_field(input.$1), input.$2);
        await tester.ensureVisible(find.text('Save Changes'));
        await tester.tap(find.text('Save Changes'));
        await tester.pumpAndSettle();
        expect(auth.writes, 0);
        expect(find.text('Edit Portfolio'), findsOneWidget);
        final widget = tester.widget<PortfolioTextField>(
          find.byWidgetPredicate(
            (widget) =>
                widget is PortfolioTextField && widget.label == input.$1,
          ),
        );
        expect(widget.errorText, isNotNull);
        expect(widget.focusNode!.hasFocus, isTrue);
        expect(
          tester.widget<TextField>(_field('Course Code')).controller!.text,
          'CS401',
        );
        await tester.pumpWidget(const SizedBox());
        service.dispose();
        auth.dispose();
      },
    );
  }

  testWidgets('valid seven-field title saves trimmed facts and returns once', (
    tester,
  ) async {
    final auth = _Auth();
    final service = PortfolioService(authService: auth);
    await _open(tester, service);
    await tester.enterText(_field('Full Name'), '  Real Student  ');
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(auth.writes, 1);
    expect(auth.submitted, _valid.toMap());
    expect(find.text('Open title page'), findsOneWidget);
    expect(find.text('Edit Portfolio'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
    auth.dispose();
  });
}

Future<void> _open(WidgetTester tester, PortfolioService service) async {
  await tester.pumpWidget(
    PortfolioScope(
      portfolioService: service,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Open title page'),
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => PortfolioInfoScreen(
                    portfolio: PortfolioRecord(
                      id: 'saved',
                      info: _valid,
                      createdAt: DateTime.utc(2026),
                      updatedAt: DateTime.utc(2026),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open title page'));
  await tester.pumpAndSettle();
}
