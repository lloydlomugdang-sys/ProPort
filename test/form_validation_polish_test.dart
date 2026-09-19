import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:proport_app/screens/auth/forgot_password_screen.dart';
import 'package:proport_app/screens/auth/new_password_screen.dart';
import 'package:proport_app/screens/auth/signup_screen.dart';
import 'package:proport_app/screens/auth/verification_code_screen.dart';
import 'package:proport_app/screens/profile/edit_profile_screen.dart';
import 'package:proport_app/screens/profile/models/user_profile_model.dart';
import 'package:proport_app/screens/profile/widgets/avatar_action_sheet.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_models.dart';
import 'package:proport_app/services/auth_scope.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/batch_upload_queue.dart';
import 'package:proport_app/services/document_models.dart';
import 'package:proport_app/services/document_service.dart';
import 'package:proport_app/services/portfolio_export_service.dart';
import 'package:proport_app/services/profile_options.dart';
import 'package:proport_app/services/secure_token_store.dart';

class _NoopTokenStore implements SecureTokenStore {
  @override
  Future<void> deleteRefreshToken() async {}

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> writeRefreshToken(String refreshToken) async {}
}

class _MockImagePicker extends Fake implements ImagePicker {
  _MockImagePicker({this.pickedFile});
  final XFile? pickedFile;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    return pickedFile;
  }
}

class _TestDocService extends DocumentService {
  _TestDocService()
    : super(
        authService: AuthService(
          apiClient: ApiClient(baseUrl: 'http://example.test:3000'),
          tokenStore: _NoopTokenStore(),
        ),
      );

  String? uploadedTitle;
  String? uploadedDescription;
  String? uploadedReflection;

  @override
  Future<DocumentOcrResult> previewOcr(dynamic fileOrFiles) async {
    return const DocumentOcrResult(
      status: DocumentOcrStatus.ready,
      rawText: 'cert text',
    );
  }

  @override
  Future<DocumentRecord> upload({
    PickedDocument? file,
    List<PickedDocument>? files,
    required String categoryKey,
    required String folderKey,
    required String title,
    required DateTime documentDate,
    String? description,
    String? reflection,
  }) async {
    uploadedTitle = title;
    uploadedDescription = description;
    uploadedReflection = reflection;
    return DocumentRecord(
      id: 'doc-1',
      title: title,
      categoryKey: categoryKey,
      folderKey: folderKey,
      documentDate: documentDate,
      originalFileName: file?.name ?? 'file.pdf',
      mimeType: file?.mimeType ?? 'application/pdf',
      fileKind: 'pdf',
      extension: 'pdf',
      sizeBytes: file?.sizeBytes ?? 1024,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      description: description,
      reflection: reflection,
    );
  }
}

class _MockProfileAuthService extends AuthService {
  _MockProfileAuthService()
    : super(
        apiClient: ApiClient(
          baseUrl: 'http://example.test:3000',
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'data': {},
                'meta': {'requestId': 'unused'},
              }),
              200,
            ),
          ),
        ),
        tokenStore: _NoopTokenStore(),
      );

  bool updateCalled = false;

  @override
  Future<ProfileOptions> fetchProfileOptions() async => const ProfileOptions(
    programs: ['BSIT', 'BSCS'],
    yearLevels: ['1st Year', '2nd Year', '3rd Year', '4th Year'],
    school: 'New Era University',
  );

  @override
  Future<AuthUser> updateCurrentUserProfile({
    required String firstName,
    required String lastName,
    required String program,
    required String yearLevel,
    required String school,
  }) async {
    updateCalled = true;
    return AuthUser(
      id: '1',
      email: 'student@example.com',
      firstName: firstName,
      lastName: lastName,
      program: program,
      yearLevel: yearLevel,
      school: school,
      status: 'active',
      emailVerifiedAt: null,
    );
  }
}

void main() {
  group('portfolioExportError mapping', () {
    test('maps 429, 500, network, timeout, and 401 correctly', () {
      expect(
        portfolioExportError(
          const ApiException(code: 'RATE_LIMITED', message: '', statusCode: 429),
        ),
        'Too many export attempts. Please wait a moment and try again.',
      );
      expect(
        portfolioExportError(
          const ApiException(code: 'SERVER_ERR', message: '', statusCode: 500),
        ),
        'The export server is temporarily unavailable. Please try again.',
      );
      expect(
        portfolioExportError(
          const ApiException(code: 'NETWORK_ERROR', message: ''),
        ),
        'Unable to connect. Check your internet connection and try again.',
      );
      expect(
        portfolioExportError(
          const ApiException(code: 'NETWORK_TIMEOUT', message: ''),
        ),
        'The export took too long to respond. Please try again.',
      );
      expect(
        portfolioExportError(
          const ApiException(code: 'UNAUTH', message: '', statusCode: 401),
        ),
        'Your session has expired. Please log in again.',
      );
      expect(
        portfolioExportError(
          const ApiException(code: 'CUSTOM', message: 'Custom error message'),
        ),
        'Custom error message',
      );
      expect(
        portfolioExportError(
          const PortfolioExportException('Export exception message'),
        ),
        'Export exception message',
      );
    });
  });

  group('BatchUploadQueue saveItem string trimming', () {
    test('trims title, description, and reflection on upload', () async {
      final docService = _TestDocService();
      final queue = BatchUploadQueue(documentService: docService);
      queue.initialize([
        PickedDocument(
          name: 'cert.pdf',
          mimeType: 'application/pdf',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      ]);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final item = queue.items.first;
      queue.updateItemMetadata(
        item.id,
        categoryKey: 'certificates',
        folderKey: 'seminars',
        title: '   Certificate of Seminar   ',
        documentDate: DateTime(2026, 1, 1),
        description: '   Attended tech conference   ',
        reflection: '   Learned about Flutter polish   ',
      );

      final success = await queue.saveItem(item.id);
      expect(success, isTrue);
      expect(docService.uploadedTitle, 'Certificate of Seminar');
      expect(docService.uploadedDescription, 'Attended tech conference');
      expect(docService.uploadedReflection, 'Learned about Flutter polish');
    });
  });

  group('Forgot Password & New Password form input polish', () {
    testWidgets('Forgot password email field validates > 320 characters', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: ForgotPasswordScreen()),
      );
      await tester.pumpAndSettle();

      final longEmail = '${'a' * 315}@example.com';
      await tester.enterText(find.byType(TextFormField), longEmail);
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email'), findsOneWidget);
    });

    testWidgets('New password fields have textInputAction next and done', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: NewPasswordScreen(resetToken: 'test-token'),
        ),
      );
      await tester.pumpAndSettle();

      final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(fields.length, 2);
      expect(fields[0].textInputAction, TextInputAction.next);
      expect(fields[1].textInputAction, TextInputAction.done);
    });
  });

  group('Edit Profile program and year level validation', () {
    testWidgets('rejects saving when program or year level is empty', (
      tester,
    ) async {
      final auth = _MockProfileAuthService();
      final profile = UserProfile(
        firstName: 'Maria',
        lastName: 'Santos',
        email: 'maria@example.com',
        program: '', // empty
        yearLevel: '', // empty
        school: 'New Era University',
      );

      await tester.pumpWidget(
        AuthScope(
          authService: auth,
          child: MaterialApp(home: EditProfileScreen(profile: profile)),
        ),
      );
      await tester.pumpAndSettle();

      // Open name dialog and change first name so _hasChanges becomes true
      await tester.tap(find.text('Maria Santos'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Maria Clara');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Try saving
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Changes'));
      await tester.pump();

      expect(find.text('Please select a supported program.'), findsOneWidget);
      expect(auth.updateCalled, isFalse);
    });
  });

  group('Avatar action sheet file format validation', () {
    testWidgets('rejects unsupported file extensions before calling API', (
      tester,
    ) async {
      final auth = _MockProfileAuthService();
      String? feedbackMessage;
      bool? isErrorFeedback;

      final picker = _MockImagePicker(
        pickedFile: XFile.fromData(
          Uint8List.fromList([1, 2, 3]),
          name: 'avatar.bmp',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAvatarActionSheet(
                context: context,
                authService: auth,
                imagePicker: picker,
                onLoadingChanged: (_) {},
                onFeedback: (msg, {bool isError = false}) {
                  feedbackMessage = msg;
                  isErrorFeedback = isError;
                },
              ),
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose from Gallery'));
      await tester.pumpAndSettle();

      expect(feedbackMessage, 'Please select a JPG, JPEG, PNG, or WebP image.');
      expect(isErrorFeedback, isTrue);
    });
  });

  group('Signup EMAIL_NOT_VERIFIED redirect', () {
    testWidgets(
      'navigates to VerificationCodeScreen without popping an error snackbar',
      (tester) async {
        final api = ApiClient(
          baseUrl: 'http://example.test:3000',
          client: MockClient((request) async {
            return http.Response(
              jsonEncode({
                'error': {
                  'code': 'EMAIL_NOT_VERIFIED',
                  'message': 'Account exists but email is not verified.',
                  'requestId': 'req-signup',
                },
              }),
              400,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        final auth = AuthService(apiClient: api, tokenStore: _NoopTokenStore());
        addTearDown(auth.dispose);

        await tester.pumpWidget(
          AuthScope(
            authService: auth,
            child: const MaterialApp(home: SignupScreen()),
          ),
        );
        await tester.pumpAndSettle();

        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), 'Juan');
        await tester.enterText(fields.at(1), 'Luna');
        await tester.enterText(fields.at(2), 'juan@example.com');
        await tester.enterText(fields.at(3), 'Password123');
        await tester.enterText(fields.at(4), 'Password123');

        await tester.ensureVisible(find.text('Sign Up'));
        await tester.tap(find.text('Sign Up'));
        await tester.pumpAndSettle();

        // Navigates to VerificationCodeScreen
        expect(find.byType(VerificationCodeScreen), findsOneWidget);
        // Does NOT show an error snackbar
        expect(find.text('Your email still needs verification.'), findsNothing);
      },
    );
  });
}
