import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:proport_app/screens/files/college_report_screen.dart';
import 'package:proport_app/screens/files/view_files_screen.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_models.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/college_report_models.dart';
import 'package:proport_app/services/college_report_scope.dart';
import 'package:proport_app/services/college_report_service.dart';
import 'package:proport_app/services/college_report_draft_store.dart';
import 'package:proport_app/services/document_scope.dart';
import 'package:proport_app/services/document_service.dart';
import 'package:proport_app/widgets/college_report_preview_status.dart';
import 'package:proport_app/widgets/primary_button.dart';

Map<String, dynamic> _fixture() =>
    jsonDecode(
          File('test/fixtures/college_report_template.json').readAsStringSync(),
        )
        as Map<String, dynamic>;
Map<String, dynamic> _envelope(Map<String, dynamic> data) => {'data': data};

class _Auth extends AuthService {
  String? owner = 'student-one';
  final Map<String, Map<String, dynamic>> reports = {};
  Completer<Map<String, dynamic>>? pendingRead;
  Completer<void>? pendingSave;
  bool failLoad = false;
  bool failSave = false;
  Object? loadError;
  bool templateReady = true;
  bool malformed = false;
  int posts = 0;
  Map<String, dynamic>? lastBody;

  @override
  AuthUser? get user => owner == null
      ? null
      : AuthUser(
          id: owner!,
          email: 'student@example.edu',
          firstName: 'Student',
          lastName: 'Fixture',
          program: '',
          yearLevel: '',
          school: '',
          status: 'active',
          emailVerifiedAt: DateTime.utc(2026),
        );
  void switchOwner(String? value) {
    owner = value;
    notifyListeners();
  }

  @override
  Future<Map<String, dynamic>> authenticatedGetJson(String path) async {
    if (loadError != null) throw loadError!;
    if (malformed) return {'data': 'invalid'};
    if (failLoad) {
      throw const ApiException(code: 'UNAVAILABLE', message: 'Test failure');
    }
    if (path.endsWith('/template')) return _envelope({'template': _fixture()});
    if (pendingRead != null) return pendingRead!.future;
    return _envelope({
      'report': reports[owner],
      'templateReady': templateReady,
      'hasLegacyReport': false,
    });
  }

  @override
  Future<Map<String, dynamic>> authenticatedPostJson(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    expect(path, '/api/v1/college-report/me');
    posts++;
    lastBody = body;
    final requestOwner = owner!;
    await pendingSave?.future;
    if (failSave) {
      throw const ApiException(code: 'UNAVAILABLE', message: 'Test failure');
    }
    final report = {...body, 'updatedAt': '2026-10-09T12:00:00.000Z'};
    reports[requestOwner] = report;
    return _envelope({'report': report});
  }
}

class _Documents extends DocumentService {
  _Documents(AuthService auth) : super(authService: auth);
  @override
  Future<void> load({bool force = false}) async {}
}

class _Drafts implements CollegeReportDraftStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String owner) async => values[owner];
  @override
  Future<void> write(String owner, String? value) async {
    if (value == null) {
      values.remove(owner);
    } else {
      values[owner] = value;
    }
  }
}

Widget _app(
  CollegeReportService service, {
  Widget child = const CollegeReportScreen(),
}) => CollegeReportScope(
  service: service,
  child: MaterialApp(home: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  test(
    'secure draft survives restart, stays out of saved export, and is owner scoped',
    () async {
      final auth = _Auth();
      final store = _Drafts();
      final first = CollegeReportService(authService: auth, draftStore: store);
      await first.load();
      first.answer('s01-q01', 'often');
      first.setEssay('Local unsaved essay');
      await first.pendingDraftWrites;
      expect(first.saved, isNull);
      expect(auth.posts, 0);
      first.dispose();
      final restarted = CollegeReportService(
        authService: auth,
        draftStore: store,
      );
      await restarted.load();
      expect(restarted.essay, 'Local unsaved essay');
      expect(restarted.answers['s01-q01'], 'often');
      expect(restarted.dirty, isTrue);
      expect(restarted.saved, isNull);
      auth.switchOwner('student-two');
      await restarted.load();
      expect(restarted.essay, isEmpty);
      expect(restarted.dirty, isFalse);
      auth.switchOwner('student-one');
      await restarted.load();
      expect(restarted.essay, 'Local unsaved essay');
      expect(await restarted.save(), isTrue);
      await restarted.pendingDraftWrites;
      expect(store.values, isEmpty);
      restarted.dispose();
      final saved = CollegeReportService(authService: auth, draftStore: store);
      await saved.load();
      expect(saved.saved!.essay, 'Local unsaved essay');
      expect(saved.dirty, isFalse);
      saved.setEssay('New unsaved text');
      await saved.pendingDraftWrites;
      expect(saved.saved!.essay, 'Local unsaved essay');
      saved.dispose();
      auth.dispose();
    },
  );

  for (final entry in <(String, int?, String)>[
    ('ROUTE_NOT_FOUND', 404, 'not available on this server'),
    ('UNAUTHORIZED', 401, 'session could not be verified'),
    ('FORBIDDEN', 403, 'session could not be verified'),
    ('COLLEGE_REPORT_NOT_CONFIGURED', 503, 'not configured'),
    ('COLLEGE_REPORT_UNAVAILABLE', 503, 'temporarily unavailable'),
    ('INTERNAL_ERROR', 500, 'unexpected College Report error'),
    ('COLD_START_TIMEOUT', null, 'may be waking up'),
    ('NETWORK_TIMEOUT', null, 'took too long'),
    ('NETWORK_OFFLINE', null, 'Network unavailable'),
    ('NETWORK_ERROR', null, 'Network unavailable'),
    ('INVALID_RESPONSE', 200, 'unexpected response'),
    ('RATE_LIMITED', 429, 'Too many requests'),
  ]) {
    test('College Report safely distinguishes ${entry.$1}', () async {
      final auth = _Auth()
        ..loadError = ApiException(
          code: entry.$1,
          statusCode: entry.$2,
          message: 'private provider details',
        );
      final service = CollegeReportService(
        authService: auth,
        draftStore: _Drafts(),
      );
      await service.load();
      expect(service.loaded, isFalse);
      expect(service.errorMessage, contains(entry.$3));
      expect(service.errorMessage, isNot(contains('private provider')));
      auth.loadError = null;
      await service.load(force: true);
      expect(service.loaded, isTrue);
      expect(service.errorMessage, isNull);
      service.dispose();
      auth.dispose();
    });
  }

  test('malformed response is not misreported as network failure', () async {
    final auth = _Auth()..malformed = true;
    final service = CollegeReportService(
      authService: auth,
      draftStore: _Drafts(),
    );
    await service.load();
    expect(service.errorMessage, contains('unexpected response'));
    expect(service.loaded, isFalse);
    service.dispose();
    auth.dispose();
  });

  testWidgets(
    'bundled questionnaire ignores obsolete template ID gating and permits explicit save',
    (tester) async {
      final auth = _Auth()..templateReady = false;
      final service = CollegeReportService(
        authService: auth,
        draftStore: _Drafts(),
      );
      await service.load();
      service.answer('s01-q01', 'often');
      service.setEssay('Keep my unsaved essay');
      final revision = service.draftRevision;
      await tester.pumpWidget(_app(service));
      expect(find.textContaining('not configured yet'), findsNothing);
      expect(find.text('Save Responses'), findsOneWidget);
      expect(service.templateReady, isTrue);
      expect(service.draftRevision, revision);
      expect(service.essay, 'Keep my unsaved essay');
      expect(service.answers['s01-q01'], 'often');
      expect(service.dirty, isTrue);
      expect(await service.save(), isTrue);
      expect(auth.reports[auth.owner]!['essay'], 'Keep my unsaved essay');
      await tester.pumpWidget(const SizedBox());
      service.dispose();
      auth.dispose();
    },
  );

  test(
    'failed and in-flight retries preserve saved answers and newer edits',
    () async {
      final auth = _Auth();
      final service = CollegeReportService(
        authService: auth,
        draftStore: _Drafts(),
      );
      await service.load();
      service.answer('s04-q01', 6);
      service.setEssay('Saved essay');
      await service.save();
      auth.failLoad = true;
      await service.load(force: true);
      expect(service.answers['s04-q01'], 6);
      expect(service.essay, 'Saved essay');
      expect(service.saved!.essay, 'Saved essay');
      auth.failLoad = false;
      auth.pendingRead = Completer<Map<String, dynamic>>();
      final retry = service.load(force: true);
      service.setEssay('Edit while retry is in flight');
      auth.pendingRead!.complete(
        _envelope({
          'report': auth.reports[auth.owner],
          'templateReady': true,
          'hasLegacyReport': false,
        }),
      );
      await retry;
      expect(service.essay, 'Edit while retry is in flight');
      expect(service.answers['s04-q01'], 6);
      expect(service.dirty, isTrue);
      service.dispose();
      auth.dispose();
    },
  );

  test(
    'complete contract parses all source groups and distinct typed scales',
    () {
      final template = CollegeReportTemplate.fromJson(_fixture());
      expect(template.questions.length, 62);
      expect(template.sections.map((s) => s.questions.length), [
        19,
        5,
        5,
        1,
        7,
        4,
        14,
        5,
        1,
        1,
      ]);
      expect(template.sections[3].options.map((o) => o.value), [
        7,
        6,
        5,
        4,
        3,
        2,
        1,
      ]);
      expect(template.sections[1].options.last.label, 'Once');
      expect(template.sections[8].responseType, 'text');
      expect(template.sections[9].options, isEmpty);
    },
  );

  test(
    'save typed/null answers and student essay; fresh service reloads exact persisted values',
    () async {
      final auth = _Auth();
      final service = CollegeReportService(
        authService: auth,
        draftStore: _Drafts(),
      );
      await service.load();
      expect(service.answers.values.every((v) => v == null), isTrue);
      service.answer('s04-q01', 6);
      service.answer('s01-q01', 'often');
      service.answer('s09-q01', 'My own response');
      service.setEssay('My own essay');
      expect(await service.save(), isTrue);
      expect(
        auth.lastBody!.keys,
        unorderedEquals(['questionnaireVersion', 'answers', 'essay']),
      );
      expect(service.saved!.answeredCount, 3);
      service.dispose();
      final reopened = CollegeReportService(
        authService: auth,
        draftStore: _Drafts(),
      );
      await reopened.load();
      expect(reopened.answers['s04-q01'], 6);
      expect(reopened.answers['s01-q01'], 'often');
      expect(reopened.answers['s02-q01'], isNull);
      expect(reopened.essay, 'My own essay');
      reopened.answer('s01-q01', null);
      reopened.answer('s09-q01', '  ');
      expect(await reopened.save(), isTrue);
      expect(reopened.saved!.answeredCount, 1);
      reopened.dispose();
      auth.dispose();
    },
  );

  test(
    'failed save keeps draft and retries; duplicate submissions cannot claim success',
    () async {
      final auth = _Auth();
      final service = CollegeReportService(
        authService: auth,
        draftStore: _Drafts(),
      );
      await service.load();
      service.answer('s05-q01', 'undecided');
      service.setEssay('Private draft');
      auth.pendingSave = Completer<void>();
      final saving = service.save();
      expect(service.isSaving, isTrue);
      expect(service.saved, isNull);
      expect(await service.save(), isFalse);
      expect(auth.posts, 1);
      auth.failSave = true;
      auth.pendingSave!.complete();
      expect(await saving, isFalse);
      expect(service.answers['s05-q01'], 'undecided');
      expect(service.essay, 'Private draft');
      expect(service.dirty, isTrue);
      expect(service.errorMessage, contains('not saved'));
      auth.failSave = false;
      auth.pendingSave = null;
      expect(await service.save(), isTrue);
      expect(service.dirty, isFalse);
      service.dispose();
      auth.dispose();
    },
  );

  test(
    'logout/account change clears private state and ignores stale load and save results',
    () async {
      final auth = _Auth();
      final service = CollegeReportService(
        authService: auth,
        draftStore: _Drafts(),
      );
      await service.load();
      service.setEssay('First student private draft');
      auth.pendingSave = Completer<void>();
      final saving = service.save();
      auth.switchOwner('student-two');
      expect(service.essay, isEmpty);
      expect(service.answers, isEmpty);
      auth.pendingSave!.complete();
      expect(await saving, isFalse);
      await service.load();
      expect(service.saved, isNull);
      expect(service.essay, isEmpty);
      auth.switchOwner('student-three');
      auth.pendingRead = Completer<Map<String, dynamic>>();
      final loading = service.load();
      auth.switchOwner(null);
      auth.pendingRead!.complete(
        _envelope({
          'report': auth.reports['student-one'],
          'templateReady': true,
        }),
      );
      await loading;
      expect(service.saved, isNull);
      expect(service.answers, isEmpty);
      expect(service.loaded, isFalse);
      service.dispose();
      auth.dispose();
    },
  );

  testWidgets(
    'renders ten sections with correct controls, null clearing and no accidental rebuild changes',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = _Auth();
      final service = CollegeReportService(
        authService: auth,
        draftStore: _Drafts(),
      );
      await service.load();
      await tester.pumpWidget(_app(service));
      expect(find.byType(ExpansionTile), findsNWidgets(10));
      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle();
      final often = find.byKey(const ValueKey('s01-q01-often'));
      await tester.ensureVisible(often);
      await tester.tap(often);
      await tester.pumpAndSettle();
      expect(service.answers['s01-q01'], 'often');
      service.setEssay('Draft');
      await tester.pump();
      expect(tester.widget<ChoiceChip>(often).selected, isTrue);
      await tester.tap(often);
      await tester.pumpAndSettle();
      expect(service.answers['s01-q01'], isNull);
      // Source section 4 is seven numeric values in descending order.
      final fourth = find.byType(ExpansionTile).at(3);
      await tester.ensureVisible(fourth);
      await tester.tap(fourth);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('s04-q01-7')), findsOneWidget);
      expect(find.byKey(const ValueKey('s04-q01-1')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
      auth.dispose();
    },
  );

  testWidgets(
    'save progress has no premature success; failure preserves fields and retry succeeds',
    (tester) async {
      final auth = _Auth();
      final service = CollegeReportService(
        authService: auth,
        draftStore: _Drafts(),
      );
      await service.load();
      await tester.pumpWidget(_app(service));
      final essay = find.widgetWithText(
        TextFormField,
        'Your essay / objectives',
      );
      await tester.ensureVisible(essay);
      await tester.enterText(essay, 'Student entered reflection');
      auth.pendingSave = Completer<void>();
      await tester.ensureVisible(find.byType(PrimaryButton));
      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();
      expect(service.isSaving, isTrue);
      expect(find.text('College Report saved.'), findsNothing);
      auth.failSave = true;
      auth.pendingSave!.complete();
      await tester.pumpAndSettle();
      expect(service.essay, 'Student entered reflection');
      expect(
        find.textContaining('Your changes were not saved.'),
        findsOneWidget,
      );
      expect(find.text('College Report saved.'), findsNothing);
      auth.failSave = false;
      auth.pendingSave = null;
      await tester.ensureVisible(find.byType(PrimaryButton));
      await tester.tap(find.byType(PrimaryButton));
      await tester.pumpAndSettle();
      expect(find.text('College Report saved.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
      final reopened = CollegeReportService(
        authService: auth,
        draftStore: _Drafts(),
      );
      await reopened.load();
      await tester.pumpWidget(_app(reopened));
      expect(find.text('Student entered reflection'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      reopened.dispose();
      auth.dispose();
    },
  );

  testWidgets(
    'loading failure is retryable and normal Files navigation opens questionnaire',
    (tester) async {
      final auth = _Auth()..failLoad = true;
      final service = CollegeReportService(
        authService: auth,
        draftStore: _Drafts(),
      );
      final documents = _Documents(auth);
      await tester.pumpWidget(
        CollegeReportScope(
          service: service,
          child: DocumentScope(
            documentService: documents,
            child: const MaterialApp(
              home: ViewFilesScreen(
                categoryKey: 'college-report',
                categoryName: 'College Report',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Answer College Report questionnaire'));
      await tester.pumpAndSettle();
      expect(find.byType(CollegeReportScreen), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      auth.failLoad = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(ExpansionTile), findsNWidgets(10));
      await tester.pumpWidget(const SizedBox());
      documents.dispose();
      service.dispose();
      auth.dispose();
    },
  );

  testWidgets(
    'preview distinguishes saved report, unsaved edits and unchanged PDF snapshots',
    (tester) async {
      final auth = _Auth();
      final service = CollegeReportService(
        authService: auth,
        draftStore: _Drafts(),
      );
      await service.load();
      await tester.pumpWidget(
        _app(
          service,
          child: const Scaffold(body: CollegeReportPreviewStatus()),
        ),
      );
      expect(
        find.textContaining('No official questionnaire saved.'),
        findsOneWidget,
      );
      service.answer('s04-q01', 7);
      await service.save();
      await tester.pumpAndSettle();
      expect(find.textContaining('1 of 62 answered'), findsOneWidget);
      expect(
        find.textContaining('existing PDFs are unchanged'),
        findsOneWidget,
      );
      service.setEssay('Still unsaved');
      await tester.pump();
      expect(
        find.text('Unsaved questionnaire edits are not included.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      service.dispose();
      auth.dispose();
    },
  );
}
