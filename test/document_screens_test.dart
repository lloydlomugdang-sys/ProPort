import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/screens/files/add_file_screen.dart';
import 'package:proport_app/screens/files/batch_review_screen.dart';
import 'package:proport_app/screens/files/document_ocr_screen.dart';
import 'package:proport_app/screens/files/files_screen.dart';
import 'package:proport_app/screens/files/view_files_screen.dart';
import 'package:proport_app/screens/files/widgets/optional_field.dart';
import 'package:proport_app/screens/files/widgets/date_picker_field.dart';
import 'package:proport_app/services/api_client.dart';
import 'package:proport_app/services/auth_service.dart';
import 'package:proport_app/services/document_models.dart';
import 'package:proport_app/services/document_picker.dart';
import 'package:proport_app/services/document_scope.dart';
import 'package:proport_app/services/document_service.dart';
import 'package:proport_app/services/secure_token_store.dart';
import 'helpers/compiled_analysis_fixture.dart';

void main() {
  testWidgets('Files renders backend categories and real folder counts', (
    tester,
  ) async {
    final service = _ScreenDocumentService(
      summary: const DocumentSummary(
        totalCount: 2,
        categoryCounts: {'certificates': 2},
        folderCounts: {'certificates/seminars': 2},
      ),
    );
    await tester.pumpWidget(_app(service, const FilesScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Certificates'), findsOneWidget);
    expect(find.text('Seminars'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Curriculum Vitae'), findsNothing);

    service.disposeWithAuth();
  });

  testWidgets('View Files shows an empty state without sample files', (
    tester,
  ) async {
    final service = _ScreenDocumentService();
    await tester.pumpWidget(_app(service, _viewFiles()));
    await tester.pumpAndSettle();

    expect(find.text('No files found.'), findsOneWidget);
    expect(find.text('sample_resume.pdf'), findsNothing);

    service.disposeWithAuth();
  });

  testWidgets(
    'View Files renders persisted metadata and deletes the owned item',
    (tester) async {
      final service = _ScreenDocumentService(documents: [_document()]);
      await tester.pumpWidget(_app(service, _viewFiles()));
      await tester.pumpAndSettle();

      expect(find.text('certificate.pdf'), findsOneWidget);
      expect(find.textContaining('2026'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(service.deletedIds, ['document-1']);
      expect(find.text('certificate.pdf'), findsNothing);
      expect(find.text('No files found.'), findsOneWidget);

      service.disposeWithAuth();
    },
  );

  testWidgets(
    'opens OCR, shows processing, saves edits, and reloads persisted text',
    (tester) async {
      final extraction = Completer<DocumentOcrResult>();
      final service = _ScreenDocumentService(
        documents: [_document()],
        extraction: extraction,
      );
      await tester.pumpWidget(_app(service, _viewFiles()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('certificate.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review extracted text'));
      await tester.pumpAndSettle();
      expect(find.text('Extracted Text'), findsOneWidget);
      expect(find.text('Extract Text'), findsOneWidget);

      await tester.tap(find.text('Extract Text'));
      await tester.pump();
      expect(find.textContaining('Extracting text locally'), findsOneWidget);
      expect(service.extractionCalls, 1);

      extraction.complete(
        const DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          rawText: 'Raw certificate text',
          reviewedText: 'Raw certificate text',
          engine: 'tesseract.js',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Raw certificate text'), findsOneWidget);
      await tester.drag(find.byType(SnackBar), const Offset(0, 200));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('ocr-reviewed-text')),
        'Corrected certificate text',
      );
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(service.savedText, 'Corrected certificate text');
      // Both the inline saved state and the confirmation notification appear.
      expect(find.text('Text changes saved.'), findsNWidgets(2));
      // Dismiss the confirmed save message before using the next route's
      // bottom action, just as a user can swipe away the floating SnackBar.
      await tester.pumpAndSettle();
      await tester.drag(find.byType(SnackBar), const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pumpAndSettle();
      await tester.tap(find.text('certificate.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review extracted text'));
      await tester.pumpAndSettle();
      expect(find.text('Corrected certificate text'), findsOneWidget);

      service.disposeWithAuth();
    },
  );

  testWidgets('requires confirmation before replacing reviewed OCR text', (
    tester,
  ) async {
    final service = _ScreenDocumentService(
      documents: [_document()],
      ocr: const DocumentOcrResult(
        status: DocumentOcrStatus.ready,
        rawText: 'Original raw text',
        reviewedText: 'Reviewed text',
        engine: 'tesseract.js',
      ),
    );
    await tester.pumpWidget(_app(service, _viewFiles()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('certificate.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review extracted text'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Extract Again'));
    await tester.tap(find.text('Extract Again'));
    await tester.pumpAndSettle();
    expect(find.text('Extract text again?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.extractionCalls, 0);

    service.disposeWithAuth();
  });

  testWidgets('shows safe scanned-PDF OCR errors without losing the file', (
    tester,
  ) async {
    final service = _ScreenDocumentService(
      documents: [_document()],
      extractionFailure: const ApiException(
        code: 'SCANNED_PDF_OCR_NOT_SUPPORTED',
        message:
            'This PDF has no embedded text. Scanned PDF OCR is not supported yet.',
        statusCode: 422,
      ),
    );
    await tester.pumpWidget(_app(service, _viewFiles()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('certificate.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review extracted text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extract Text'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('upload the page as JPG or PNG'),
      findsOneWidget,
    );
    expect(service.documents.single.id, 'document-1');
    expect(find.text('Try Again'), findsOneWidget);

    service.disposeWithAuth();
  });

  testWidgets('shows a safe authentication failure during OCR', (tester) async {
    final service = _ScreenDocumentService(
      documents: [_document()],
      extractionFailure: const ApiException(
        code: 'UNAUTHORIZED',
        message: 'Your session has expired. Please log in again.',
        statusCode: 401,
      ),
    );
    await tester.pumpWidget(_app(service, _viewFiles()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('certificate.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review extracted text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extract Text'));
    await tester.pumpAndSettle();

    expect(
      find.text('Your session has expired. Please log in again.'),
      findsOneWidget,
    );
    expect(service.documents.single.id, 'document-1');

    service.disposeWithAuth();
  });

  testWidgets('Add File picks a native file and uploads selected metadata', (
    tester,
  ) async {
    final service = _ScreenDocumentService();
    final bytes = Uint8List.fromList('%PDF-GradPort'.codeUnits);
    final picker = _FakePicker(
      PickedDocument(
        name: 'demo.pdf',
        mimeType: 'application/pdf',
        bytes: bytes,
      ),
    );
    await tester.pumpWidget(_app(service, AddFileScreen(filePicker: picker)));
    await tester.pumpAndSettle();

    await _completeUploadForm(tester);
    await tester.tap(find.text('Add File'));
    await tester.pump();

    expect(picker.calls, 1);
    expect(service.uploadedFile?.name, 'demo.pdf');
    expect(service.uploadedFile?.bytes, same(bytes));
    expect(service.uploadedCategoryKey, 'certificates');
    expect(service.uploadedFolderKey, 'seminars');
    expect(service.uploadedTitle, 'Demo Certificate');
    expect(service.uploadedDate, isNotNull);
    expect(service.summary.totalCount, 1);

    service.disposeWithAuth();
  });

  testWidgets(
    'Add File shows a safe API error and does not add failed uploads',
    (tester) async {
      final service = _ScreenDocumentService(
        uploadFailure: const ApiException(
          code: 'DOCUMENT_UNAVAILABLE',
          message: 'Documents are temporarily unavailable. Please try again.',
          statusCode: 503,
        ),
      );
      final picker = _FakePicker(
        PickedDocument(
          name: 'demo.pdf',
          mimeType: 'application/pdf',
          bytes: Uint8List.fromList('%PDF-GradPort'.codeUnits),
        ),
      );
      await tester.pumpWidget(_app(service, AddFileScreen(filePicker: picker)));
      await tester.pumpAndSettle();

      await _completeUploadForm(tester);
      await tester.tap(find.text('Add File'));
      await tester.pump();

      expect(
        find.text('Documents are temporarily unavailable. Please try again.'),
        findsOneWidget,
      );
      expect(service.documents, isEmpty);
      expect(service.summary.totalCount, 0);

      service.disposeWithAuth();
    },
  );

  testWidgets(
    'OCR fills blank fields with editable suggestions and leaves reflection blank',
    (tester) async {
      final service = _ScreenDocumentService(ocr: _suggestedOcr());
      await _openSuggestionForm(tester, service);
      await tester.pumpAndSettle();

      expect(service.previewCalls, 1);
      expect(find.text('Suggest details from OCR'), findsNothing);
      expect(find.textContaining('Unable to reach the server'), findsNothing);
      expect(
        find.text('Suggested from OCR — review before adding your file.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byType(DropdownButton<String>).first,
            )
            .value,
        'Certificates',
      );
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byType(DropdownButton<String>).last,
            )
            .value,
        'Seminars',
      );
      expect(
        tester
            .widget<DatePickerField>(find.byType(DatePickerField))
            .selectedDate,
        DateTime(2026, 9, 14),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Digital Records Management',
      );
      final optional = tester
          .widgetList<OptionalField>(find.byType(OptionalField))
          .toList();
      expect(
        optional[0].controller.text,
        'Certificate of Completion for Digital Records Management.',
      );
      expect(optional[0].isEnabled, isTrue);
      expect(optional[1].controller.text, isEmpty);
      expect(optional[1].isEnabled, isFalse);

      await tester.ensureVisible(find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, 'My edited title');
      await tester.ensureVisible(find.text('Add File'));
      await tester.tap(find.text('Add File'));
      await tester.pump();
      expect(service.uploadedTitle, 'My edited title');
      expect(service.uploadedDate, DateTime(2026, 9, 14));
      expect(
        service.uploadedDescription,
        contains('Digital Records Management'),
      );
      expect(service.uploadedReflection, isNull);
      service.disposeWithAuth();
    },
  );

  testWidgets(
    'OCR preserves edits made while processing; explicit Apply can replace metadata only',
    (tester) async {
      final pending = Completer<DocumentOcrResult>();
      final service = _ScreenDocumentService(extraction: pending);
      await _openSuggestionForm(tester, service, settle: false);
      await tester.pump();
      expect(find.text('Reading document...'), findsOneWidget);
      await tester.ensureVisible(find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, 'My personal title');
      final dateField = tester.widget<DatePickerField>(
        find.byType(DatePickerField),
      );
      dateField.onDateSelected(DateTime(2025, 3, 4));
      final optional = tester
          .widgetList<OptionalField>(find.byType(OptionalField))
          .toList();
      optional[0].controller.text = 'My description';
      optional[1].controller.text = 'My reflection';
      optional[1].onToggle();
      pending.complete(_suggestedOcr());
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'My personal title',
      );
      expect(optional[0].controller.text, 'My description');
      expect(
        tester
            .widget<DatePickerField>(find.byType(DatePickerField))
            .selectedDate,
        DateTime(2025, 3, 4),
      );
      expect(optional[1].controller.text, 'My reflection');

      await tester.ensureVisible(find.text('Apply OCR suggestions'));
      await tester.tap(find.text('Apply OCR suggestions'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Digital Records Management',
      );
      expect(
        optional[0].controller.text,
        contains('Certificate of Completion'),
      );
      expect(optional[1].controller.text, 'My reflection');
      expect(
        tester
            .widget<DatePickerField>(find.byType(DatePickerField))
            .selectedDate,
        DateTime(2026, 9, 14),
      );
      service.disposeWithAuth();
    },
  );

  testWidgets(
    'unknown category/folder suggestions are not added to dropdowns; partial title is useful',
    (tester) async {
      final service = _ScreenDocumentService(
        ocr: const DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          metadataSuggestions: DocumentMetadataSuggestions(
            categoryKey: 'invented',
            folderKey: 'invented',
            title: 'Only a detected title',
          ),
        ),
      );
      await _openSuggestionForm(tester, service);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byType(DropdownButton<String>).first,
            )
            .value,
        isNull,
      );
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byType(DropdownButton<String>).last,
            )
            .value,
        isNull,
      );
      expect(
        tester
            .widget<DatePickerField>(find.byType(DatePickerField))
            .selectedDate,
        isNull,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Only a detected title',
      );
      service.disposeWithAuth();
    },
  );

  testWidgets(
    'automatic suggestions preserve an explicitly selected content and folder',
    (tester) async {
      final pending = Completer<DocumentOcrResult>();
      final service = _ScreenDocumentService(extraction: pending);
      await _openSuggestionForm(tester, service, settle: false);
      tester
          .widget<DropdownButton<String>>(
            find.byType(DropdownButton<String>).first,
          )
          .onChanged!('Accomplishments');
      await tester.pump();
      tester
          .widget<DropdownButton<String>>(
            find.byType(DropdownButton<String>).last,
          )
          .onChanged!('Projects');
      await tester.pump();
      pending.complete(_suggestedOcr());
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byType(DropdownButton<String>).first,
            )
            .value,
        'Accomplishments',
      );
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byType(DropdownButton<String>).last,
            )
            .value,
        'Projects',
      );
      await tester.ensureVisible(find.text('Apply OCR suggestions'));
      await tester.tap(find.text('Apply OCR suggestions'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byType(DropdownButton<String>).first,
            )
            .value,
        'Certificates',
      );
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byType(DropdownButton<String>).last,
            )
            .value,
        'Seminars',
      );
      service.disposeWithAuth();
    },
  );

  testWidgets(
    'empty suggestions leave all fields empty without fake defaults',
    (tester) async {
      final service = _ScreenDocumentService(
        ocr: const DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          metadataSuggestions: DocumentMetadataSuggestions(),
        ),
      );
      await _openSuggestionForm(tester, service);
      await tester.pumpAndSettle();
      expect(
        find.text('No reliable details found. You can enter them manually.'),
        findsOneWidget,
      );
      expect(find.text('Apply OCR suggestions'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
      expect(
        tester
            .widget<DatePickerField>(find.byType(DatePickerField))
            .selectedDate,
        isNull,
      );
      service.disposeWithAuth();
    },
  );

  testWidgets('OCR failure allows manual upload with safe error feedback', (
    tester,
  ) async {
    final service = _ScreenDocumentService(
      extractionFailure: const ApiException(
        code: 'OCR_TIMEOUT',
        message:
            'Text extraction took too long. Please try a smaller document.',
        statusCode: 504,
      ),
    );
    await _openSuggestionForm(tester, service);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Automatic reading timed out while processing this file. Please retry, or enter the details manually.',
      ),
      findsOneWidget,
    );
    await _completeUploadForm(tester, pick: false);
    await tester.tap(find.text('Add File'));
    await tester.pump();
    expect(service.uploadedTitle, 'Demo Certificate');
    service.disposeWithAuth();
  });

  testWidgets('changing the picked file discards a stale preview response', (
    tester,
  ) async {
    final pending = Completer<DocumentOcrResult>();
    final service = _ScreenDocumentService(extraction: pending);
    service.previewResponses.addAll([
      pending.future,
      Future.value(const DocumentOcrResult(status: DocumentOcrStatus.ready)),
    ]);
    await _openSuggestionForm(tester, service, settle: false);
    await tester.pump();
    await tester.tap(find.text('demo.pdf'));
    await tester.pump();
    pending.complete(_suggestedOcr());
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      isEmpty,
    );
    expect(find.text('Apply OCR suggestions'), findsNothing);
    service.disposeWithAuth();
  });

  testWidgets(
    'AI recommendations are labeled, editable and never fill Reflection',
    (tester) async {
      final suggestions = _suggestedOcr().metadataSuggestions;
      final service = _ScreenDocumentService(
        ocr: DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          metadataSuggestions: suggestions,
          metadataAnalysis: const DocumentMetadataAnalysis(
            source: 'gemini',
            aiStatus: 'success',
          ),
        ),
      );
      await _openSuggestionForm(tester, service);
      expect(
        find.text(
          'AI suggested from document — review and edit before saving.',
        ),
        findsOneWidget,
      );
      expect(find.text('Apply AI suggestions'), findsNothing);
      expect(find.text('Reapply AI suggestions'), findsNothing);
      expect(
        find.textContaining('AI suggestions are temporarily unavailable'),
        findsNothing,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Digital Records Management',
      );
      expect(find.textContaining('Unable to reach the server'), findsNothing);
      final fields = tester
          .widgetList<OptionalField>(find.byType(OptionalField))
          .toList();
      expect(fields[1].controller.text, isEmpty);
      fields[1].controller.text = 'My own reflection';
      await tester.pump();
      expect(find.text('Reapply AI suggestions'), findsNothing);
      await tester.ensureVisible(find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, 'My reviewed title');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'My reviewed title',
      );
      expect(find.text('Reapply AI suggestions'), findsOneWidget);
      // Even a deliberately cleared field must survive later service updates.
      await tester.enterText(find.byType(TextField).first, '');
      service.notifyListeners();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
      fields[1].controller.text = 'My own reflection';
      await tester.ensureVisible(find.text('Reapply AI suggestions'));
      await tester.tap(find.text('Reapply AI suggestions'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Digital Records Management',
      );
      expect(fields[1].controller.text, 'My own reflection');
      expect(find.text('Reapply AI suggestions'), findsNothing);
      expect(service.previewCalls, 1);
      service.disposeWithAuth();
    },
  );

  testWidgets(
    'AI outage applies basic details without an OCR or network failure',
    (tester) async {
      final service = _ScreenDocumentService(
        ocr: DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          metadataSuggestions: _suggestedOcr().metadataSuggestions,
          metadataAnalysis: const DocumentMetadataAnalysis(
            source: 'rules',
            aiStatus: 'unavailable',
          ),
        ),
      );
      await _openSuggestionForm(tester, service);
      expect(
        find.text(
          'AI suggestions are temporarily unavailable. Basic document details were applied where possible.',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Digital Records Management',
      );
      expect(find.text('Apply AI suggestions'), findsNothing);
      expect(find.textContaining('AI suggested from document'), findsNothing);
      expect(
        find.textContaining("We couldn't automatically read"),
        findsNothing,
      );
      expect(find.textContaining('Unable to reach the server'), findsNothing);
      service.disposeWithAuth();
    },
  );

  for (final type in [
    ('jpg', 'image/jpeg'),
    ('jpeg', 'image/jpeg'),
    ('png', 'image/png'),
    ('pdf', 'application/pdf'),
  ]) {
    testWidgets(
      'selecting ${type.$1} automatically requests exactly one preview',
      (tester) async {
        final pending = Completer<DocumentOcrResult>();
        final service = _ScreenDocumentService(extraction: pending);
        final file = PickedDocument(
          name: 'selected.${type.$1}',
          mimeType: type.$2,
          bytes: Uint8List(8),
        );
        await tester.pumpWidget(
          _app(service, AddFileScreen(filePicker: _FakePicker(file))),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add pages to one document'));
        await tester.pump();
        expect(service.previewCalls, 1);
        expect(service.previewFiles.single, same(file));
        expect(find.text('Reading document...'), findsOneWidget);
        pending.complete(_suggestedOcr());
        await tester.pumpAndSettle();
        expect(find.text('Reading document...'), findsNothing);
        expect(find.textContaining('Unable to reach the server'), findsNothing);
        expect(service.previewCalls, 1);
        service.disposeWithAuth();
      },
    );
  }

  testWidgets(
    'new file replaces earlier automatic fields and preserves manual edits',
    (tester) async {
      final service = _ScreenDocumentService(ocr: _suggestedOcr());
      final picker = await _openSuggestionForm(tester, service);
      await tester.ensureVisible(find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, 'My own title');
      final optional = tester
          .widgetList<OptionalField>(find.byType(OptionalField))
          .toList();
      optional[1].controller.text = 'Personal reflection';
      final pending = Completer<DocumentOcrResult>();
      service.previewResponses.add(pending.future);
      picker.result = PickedDocument(
        name: 'new.png',
        mimeType: 'image/png',
        bytes: Uint8List(8),
      );
      await tester.ensureVisible(find.text('demo.pdf'));
      await tester.tap(find.text('demo.pdf'));
      await tester.pump();
      expect(
        tester
            .widget<DatePickerField>(find.byType(DatePickerField))
            .selectedDate,
        isNull,
      );
      expect(optional[0].controller.text, isEmpty);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'My own title',
      );
      pending.complete(
        DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          metadataSuggestions: DocumentMetadataSuggestions(
            categoryKey: 'certificates',
            folderKey: 'trainings',
            title: 'New automatic title',
            documentDate: DateTime(2026, 10, 15),
            description: 'New detected description',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(service.previewFiles.map((file) => file.name), [
        'demo.pdf',
        'new.png',
      ]);
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byType(DropdownButton<String>).last,
            )
            .value,
        'Trainings',
      );
      expect(
        tester
            .widget<DatePickerField>(find.byType(DatePickerField))
            .selectedDate,
        DateTime(2026, 10, 15),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'My own title',
      );
      expect(optional[0].controller.text, 'New detected description');
      expect(optional[1].controller.text, 'Personal reflection');
      service.disposeWithAuth();
    },
  );

  testWidgets(
    'failure for an older file cannot replace newer successful suggestions',
    (tester) async {
      final old = Completer<DocumentOcrResult>();
      final service = _ScreenDocumentService()
        ..previewResponses.addAll([old.future, Future.value(_suggestedOcr())]);
      final picker = await _openSuggestionForm(tester, service, settle: false);
      picker.result = PickedDocument(
        name: 'new.png',
        mimeType: 'image/png',
        bytes: Uint8List(8),
      );
      await tester.tap(find.text('demo.pdf'));
      await tester.pumpAndSettle();
      old.completeError(
        const ApiException(
          code: 'NETWORK_ERROR',
          message: 'Unable to reach the server.',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Unable to reach the server'), findsNothing);
      expect(
        find.textContaining("We couldn't automatically read"),
        findsNothing,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Digital Records Management',
      );
      service.disposeWithAuth();
    },
  );

  testWidgets('Add File rejects unsupported and oversized picker results', (
    tester,
  ) async {
    final service = _ScreenDocumentService();
    final unsupported = _FakePicker(
      PickedDocument(
        name: 'notes.txt',
        mimeType: 'text/plain',
        bytes: Uint8List(1),
      ),
    );
    await tester.pumpWidget(
      _app(service, AddFileScreen(filePicker: unsupported)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tap to upload file'));
    await tester.pump();
    expect(
      find.text('Please select a PDF, JPG, JPEG, or PNG file.'),
      findsOneWidget,
    );
    expect(find.text('notes.txt'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    service.disposeWithAuth();

    final oversizedService = _ScreenDocumentService();
    final oversized = _FakePicker(
      PickedDocument(
        name: 'large.pdf',
        mimeType: 'application/pdf',
        bytes: Uint8List(DocumentService.maxUploadBytes + 1),
      ),
    );
    await tester.pumpWidget(
      _app(oversizedService, AddFileScreen(filePicker: oversized)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tap to upload file'));
    await tester.pump();
    expect(
      find.text('The selected file exceeds the 15 MB upload limit.'),
      findsOneWidget,
    );
    expect(find.text('large.pdf'), findsNothing);

    oversizedService.disposeWithAuth();
  });

  testWidgets(
    'suggests Curriculum Vitae for CV documents and maps folder properly',
    (tester) async {
      final cvCategories = [
        const DocumentCategory(
          key: 'curriculum-vitae',
          name: 'Curriculum Vitae',
          folders: [
            DocumentFolder(key: 'curriculum-vitae', name: 'Curriculum Vitae'),
          ],
        ),
        const DocumentCategory(
          key: 'certificates',
          name: 'Certificates',
          folders: [
            DocumentFolder(key: 'seminars', name: 'Seminars'),
            DocumentFolder(key: 'trainings', name: 'Trainings'),
          ],
        ),
      ];
      final cvOcr = DocumentOcrResult(
        status: DocumentOcrStatus.ready,
        metadataSuggestions: DocumentMetadataSuggestions(
          categoryKey: 'curriculum-vitae',
          folderKey: 'curriculum-vitae',
          title: 'Curriculum Vitae - Juan Dela Cruz',
          documentDate: DateTime(2026, 9, 15),
          description: 'Professional resume and curriculum vitae.',
        ),
      );
      final service = _ScreenDocumentService(
        categories: cvCategories,
        ocr: cvOcr,
      );
      await _openSuggestionForm(tester, service);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byType(DropdownButton<String>).first,
            )
            .value,
        'Curriculum Vitae',
      );
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byType(DropdownButton<String>).last,
            )
            .value,
        'Curriculum Vitae',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Curriculum Vitae - Juan Dela Cruz',
      );
      service.disposeWithAuth();
    },
  );

  testWidgets(
    'manual reflection is never overwritten or cleared when suggestions apply or reapply',
    (tester) async {
      final pending = Completer<DocumentOcrResult>();
      final service = _ScreenDocumentService(extraction: pending);
      await _openSuggestionForm(tester, service, settle: false);
      await tester.pump();

      // Enable and type a manual reflection
      await tester.ensureVisible(find.text('Reflection'));
      await tester.tap(find.text('Reflection'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final reflectionField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Enter reflection',
      );
      expect(reflectionField, findsOneWidget);
      await tester.enterText(
        reflectionField,
        'My sacred personal reflection on learning.',
      );
      await tester.pump();

      // Now complete the OCR suggestions
      pending.complete(_suggestedOcr());
      await tester.pumpAndSettle();

      // Reflection remains intact!
      expect(
        find.text('My sacred personal reflection on learning.'),
        findsOneWidget,
      );

      // Reapply suggestions if available
      final reapply = find.text('Reapply OCR suggestions');
      if (reapply.evaluate().isNotEmpty) {
        await tester.tap(reapply);
        await tester.pumpAndSettle();
        expect(
          find.text('My sacred personal reflection on learning.'),
          findsOneWidget,
        );
      }

      service.disposeWithAuth();
    },
  );

  testWidgets(
    'multi-page image addition re-runs OCR across all pages, refines auto-filled metadata while preserving manual overrides, and persists OCR + multi-page previews on save',
    (tester) async {
      final page1 = PickedDocument(
        name: 'page1.jpg',
        mimeType: 'image/jpeg',
        bytes: _validPngBytes,
      );
      final page2 = PickedDocument(
        name: 'page2.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([..._validPngBytes, 0x00]),
      );

      final service = _ScreenDocumentService()
        ..previewResponses.addAll([
          Future.value(
            const DocumentOcrResult(
              status: DocumentOcrStatus.ready,
              rawText:
                  'Republic of the Philippines\nCertificate of Participation',
              reviewedText:
                  'Republic of the Philippines\nCertificate of Participation',
              engine: 'tesseract.js',
              pages: [
                DocumentOcrPage(
                  pageNumber: 1,
                  status: 'ready',
                  originalFileName: 'page1.jpg',
                  mimeType: 'image/jpeg',
                  rawText:
                      'Republic of the Philippines\nCertificate of Participation',
                ),
              ],
              metadataSuggestions: DocumentMetadataSuggestions(
                categoryKey: 'certificates',
                folderKey: 'trainings',
              ),
              metadataAnalysis: DocumentMetadataAnalysis(
                source: 'gemini',
                aiStatus: 'success',
              ),
            ),
          ),
          Future.value(
            DocumentOcrResult(
              status: DocumentOcrStatus.ready,
              rawText:
                  '--- Page 1 ---\nRepublic of the Philippines\nCertificate of Participation\n\n--- Page 2 ---\nNational Cloud Architecture Workshop\nHeld on April 15, 2026',
              reviewedText:
                  '--- Page 1 ---\nRepublic of the Philippines\nCertificate of Participation\n\n--- Page 2 ---\nNational Cloud Architecture Workshop\nHeld on April 15, 2026',
              engine: 'tesseract.js',
              pages: const [
                DocumentOcrPage(
                  pageNumber: 1,
                  status: 'ready',
                  originalFileName: 'page1.jpg',
                  mimeType: 'image/jpeg',
                  rawText:
                      'Republic of the Philippines\nCertificate of Participation',
                ),
                DocumentOcrPage(
                  pageNumber: 2,
                  status: 'ready',
                  originalFileName: 'page2.png',
                  mimeType: 'image/png',
                  rawText:
                      'National Cloud Architecture Workshop\nHeld on April 15, 2026',
                ),
              ],
              metadataSuggestions: DocumentMetadataSuggestions(
                categoryKey: 'certificates',
                folderKey: 'trainings',
                title: 'National Cloud Architecture Workshop',
                documentDate: DateTime(2026, 4, 15),
                description: '2-day hands-on cloud architecture workshop.',
              ),
              metadataAnalysis: const DocumentMetadataAnalysis(
                source: 'gemini',
                aiStatus: 'success',
              ),
            ),
          ),
        ]);

      final picker = _FakePicker(page1);
      await tester.pumpWidget(_app(service, AddFileScreen(filePicker: picker)));
      await tester.pumpAndSettle();

      // 1. Pick Page 1 (JPEG)
      await tester.tap(find.text('Add pages to one document'));
      await tester.pumpAndSettle();

      expect(service.previewCalls, 1);
      expect(service.previewFileBatches.single.map((f) => f.name).toList(), [
        'page1.jpg',
      ]);
      // Content & Folder auto-filled from Page 1, Title & Date still blank
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byType(DropdownButton<String>).first,
            )
            .value,
        'Certificates',
      );
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byType(DropdownButton<String>).last,
            )
            .value,
        'Trainings',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );

      // 2. Manually override Folder to 'Seminars'
      await tester.ensureVisible(find.byType(DropdownButton<String>).last);
      await tester.tap(find.byType(DropdownButton<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Seminars').last);
      await tester.pumpAndSettle();

      // 3. Add Page 2 (PNG)
      picker.result = page2;
      await tester.ensureVisible(
        find.text('Add pages to this document (1/10)'),
      );
      await tester.tap(find.text('Add pages to this document (1/10)'));
      await tester.pumpAndSettle();

      expect(find.text('Document Pages (2)'), findsOneWidget);
      expect(service.previewCalls, 2);
      expect(service.previewFileBatches.last.map((f) => f.name).toList(), [
        'page1.jpg',
        'page2.png',
      ]);

      // Combined OCR across Page 1 + Page 2 populates Title & Date while keeping manual Folder override ('Seminars')
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'National Cloud Architecture Workshop',
      );
      expect(
        tester
            .widget<DatePickerField>(find.byType(DatePickerField))
            .selectedDate,
        DateTime(2026, 4, 15),
      );
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byType(DropdownButton<String>).last,
            )
            .value,
        'Seminars',
      );

      // 4. Save the document
      await tester.ensureVisible(find.text('Add File'));
      await tester.tap(find.text('Add File'));
      await tester.pumpAndSettle();

      expect(service.uploadedFiles.map((f) => f.name).toList(), [
        'page1.jpg',
        'page2.png',
      ]);
      expect(service.uploadedFolderKey, 'seminars');
      expect(service.uploadedTitle, 'National Cloud Architecture Workshop');

      // 5. Reopen DocumentOcrScreen (Document Details) and verify OCR text & both page previews are immediately ready
      final savedDoc = service.documents.first;
      expect(savedDoc.pageCount, 2);
      expect(service.getCachedContent(savedDoc.id), equals(page1.bytes));
      expect(
        service.getCachedContent(savedDoc.id, attachmentId: '2'),
        equals(page2.bytes),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _app(service, DocumentOcrScreen(document: savedDoc)),
      );
      await tester.pumpAndSettle();

      expect(find.text('No extracted text yet.'), findsNothing);
      expect(find.textContaining('--- Page 1 ---'), findsOneWidget);
      expect(
        find.textContaining('National Cloud Architecture Workshop'),
        findsOneWidget,
      );
      expect(find.text('Page 1 of 2'), findsOneWidget);

      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 2'), findsOneWidget);

      service.disposeWithAuth();
    },
  );

  testWidgets(
    'reordering image pages before saving updates combined OCR page order and uploads files in the new order',
    (tester) async {
      final page1 = PickedDocument(
        name: 'page1.jpg',
        mimeType: 'image/jpeg',
        bytes: _validPngBytes,
      );
      final page2 = PickedDocument(
        name: 'page2.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([..._validPngBytes, 0x01]),
      );

      final service = _ScreenDocumentService()
        ..previewResponses.addAll([
          Future.value(
            const DocumentOcrResult(
              status: DocumentOcrStatus.ready,
              rawText: 'First image text',
              reviewedText: 'First image text',
              engine: 'tesseract.js',
              pages: [
                DocumentOcrPage(
                  pageNumber: 1,
                  status: 'ready',
                  originalFileName: 'page1.jpg',
                  mimeType: 'image/jpeg',
                  rawText: 'First image text',
                ),
              ],
            ),
          ),
          Future.value(
            DocumentOcrResult(
              status: DocumentOcrStatus.ready,
              rawText:
                  '--- Page 1 ---\nFirst image text\n\n--- Page 2 ---\nSecond image text',
              reviewedText:
                  '--- Page 1 ---\nFirst image text\n\n--- Page 2 ---\nSecond image text',
              engine: 'tesseract.js',
              pages: const [
                DocumentOcrPage(
                  pageNumber: 1,
                  status: 'ready',
                  originalFileName: 'page1.jpg',
                  mimeType: 'image/jpeg',
                  rawText: 'First image text',
                ),
                DocumentOcrPage(
                  pageNumber: 2,
                  status: 'ready',
                  originalFileName: 'page2.png',
                  mimeType: 'image/png',
                  rawText: 'Second image text',
                ),
              ],
              metadataSuggestions: DocumentMetadataSuggestions(
                categoryKey: 'certificates',
                folderKey: 'seminars',
                title: 'Reordered Certificate',
                documentDate: DateTime(2026, 5, 10),
              ),
            ),
          ),
          Future.value(
            DocumentOcrResult(
              status: DocumentOcrStatus.ready,
              rawText:
                  '--- Page 1 ---\nSecond image text\n\n--- Page 2 ---\nFirst image text',
              reviewedText:
                  '--- Page 1 ---\nSecond image text\n\n--- Page 2 ---\nFirst image text',
              engine: 'tesseract.js',
              pages: const [
                DocumentOcrPage(
                  pageNumber: 1,
                  status: 'ready',
                  originalFileName: 'page2.png',
                  mimeType: 'image/png',
                  rawText: 'Second image text',
                ),
                DocumentOcrPage(
                  pageNumber: 2,
                  status: 'ready',
                  originalFileName: 'page1.jpg',
                  mimeType: 'image/jpeg',
                  rawText: 'First image text',
                ),
              ],
              metadataSuggestions: DocumentMetadataSuggestions(
                categoryKey: 'certificates',
                folderKey: 'seminars',
                title: 'Reordered Certificate',
                documentDate: DateTime(2026, 5, 10),
              ),
            ),
          ),
        ]);

      final picker = _FakePicker(page1);
      await tester.pumpWidget(_app(service, AddFileScreen(filePicker: picker)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add pages to one document'));
      await tester.pumpAndSettle();

      picker.result = page2;
      await tester.ensureVisible(
        find.text('Add pages to this document (1/10)'),
      );
      await tester.tap(find.text('Add pages to this document (1/10)'));
      await tester.pumpAndSettle();

      // Reorder: move Page 2 up to become Page 1
      await tester.ensureVisible(find.byTooltip('Move page up'));
      await tester.tap(find.byTooltip('Move page up'));
      await tester.pumpAndSettle();

      expect(service.previewFileBatches.last.map((f) => f.name).toList(), [
        'page2.png',
        'page1.jpg',
      ]);

      await tester.ensureVisible(find.text('Add File'));
      await tester.tap(find.text('Add File'));
      await tester.pumpAndSettle();

      expect(service.uploadedFiles.map((f) => f.name).toList(), [
        'page2.png',
        'page1.jpg',
      ]);

      final savedDoc = service.documents.first;
      final persistedOcr = service.ocrFor(savedDoc.id);
      expect(persistedOcr, isNotNull);
      expect(
        persistedOcr!.rawText,
        '--- Page 1 ---\nSecond image text\n\n--- Page 2 ---\nFirst image text',
      );

      service.disposeWithAuth();
    },
  );

  testWidgets(
    'partial OCR failure on multi-page images preserves readable pages and shows retry notice',
    (tester) async {
      final page1 = PickedDocument(
        name: 'page1.jpg',
        mimeType: 'image/jpeg',
        bytes: _validPngBytes,
      );
      final page2 = PickedDocument(
        name: 'unreadable.png',
        mimeType: 'image/png',
        bytes: _validPngBytes,
      );

      final service = _ScreenDocumentService()
        ..previewResponses.addAll([
          Future.value(
            DocumentOcrResult(
              status: DocumentOcrStatus.ready,
              rawText: 'Readable certificate page',
              reviewedText: 'Readable certificate page',
              engine: 'tesseract.js',
              pages: const [
                DocumentOcrPage(
                  pageNumber: 1,
                  status: 'ready',
                  originalFileName: 'page1.jpg',
                  mimeType: 'image/jpeg',
                  rawText: 'Readable certificate page',
                ),
              ],
              metadataSuggestions: DocumentMetadataSuggestions(
                categoryKey: 'certificates',
                folderKey: 'seminars',
                title: 'Readable Certificate',
                documentDate: DateTime(2026, 6, 1),
              ),
            ),
          ),
          Future.value(
            DocumentOcrResult(
              status: DocumentOcrStatus.ready,
              rawText: '--- Page 1 ---\nReadable certificate page',
              reviewedText: '--- Page 1 ---\nReadable certificate page',
              engine: 'tesseract.js',
              pages: const [
                DocumentOcrPage(
                  pageNumber: 1,
                  status: 'ready',
                  originalFileName: 'page1.jpg',
                  mimeType: 'image/jpeg',
                  rawText: 'Readable certificate page',
                ),
                DocumentOcrPage(
                  pageNumber: 2,
                  status: 'failed',
                  originalFileName: 'unreadable.png',
                  mimeType: 'image/png',
                ),
              ],
              metadataSuggestions: DocumentMetadataSuggestions(
                categoryKey: 'certificates',
                folderKey: 'seminars',
                title: 'Readable Certificate',
                documentDate: DateTime(2026, 6, 1),
              ),
            ),
          ),
        ]);

      final picker = _FakePicker(page1);
      await tester.pumpWidget(_app(service, AddFileScreen(filePicker: picker)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add pages to one document'));
      await tester.pumpAndSettle();

      picker.result = page2;
      await tester.ensureVisible(
        find.text('Add pages to this document (1/10)'),
      );
      await tester.tap(find.text('Add pages to this document (1/10)'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Page 2 could not be read automatically. Readable pages were used; you can retry or continue.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry automatic reading'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Readable Certificate',
      );

      service.disposeWithAuth();
    },
  );

  testWidgets(
    'primary Add File + one selected JPEG uses the same queue review and OCR as multiple files',
    (tester) async {
      final doc = PickedDocument(
        name: 'single.jpg',
        mimeType: 'image/jpeg',
        bytes: _validPngBytes,
      );
      final service = _ScreenDocumentService();
      final picker = _FakePicker(doc);

      await tester.pumpWidget(_app(service, AddFileScreen(filePicker: picker)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tap to upload file'));
      await tester.pumpAndSettle();

      expect(find.byType(AddFileScreen), findsNothing);
      expect(find.byType(BatchReviewScreen), findsOneWidget);
      expect(find.text('single.jpg'), findsOneWidget);
      expect(find.text('Review Files (0/1)'), findsOneWidget);
      expect(find.text('Processing: 1 Document'), findsOneWidget);
      expect(find.text('Document 1 of 1'), findsOneWidget);
      expect(service.previewCalls, 1);
      expect(service.previewFileBatches.single, [doc]);
      expect(service.uploadedFiles, isEmpty);

      service.disposeWithAuth();
    },
  );

  testWidgets(
    'primary Add File + two selected files routes to Review Files batch screen with separate documents',
    (tester) async {
      final file1 = PickedDocument(
        name: 'cert1.pdf',
        mimeType: 'application/pdf',
        bytes: _validPngBytes,
      );
      final file2 = PickedDocument(
        name: 'award.jpg',
        mimeType: 'image/jpeg',
        bytes: _validPngBytes,
      );
      final service = _ScreenDocumentService();
      final picker = _FakePicker(file1, multiResult: [file1, file2]);

      await tester.pumpWidget(_app(service, AddFileScreen(filePicker: picker)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tap to upload file'));
      await tester.pumpAndSettle();

      expect(find.byType(BatchReviewScreen), findsOneWidget);
      expect(find.textContaining('Processing: 2 Documents'), findsOneWidget);
      expect(service.previewCalls, 2);
      expect(service.previewFileBatches, [
        [file1],
        [file2],
      ]);
      expect(find.text('cert1.pdf'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('award.jpg'), findsOneWidget);

      service.disposeWithAuth();
    },
  );

  testWidgets(
    'batch auto-categorization behavior remains intact during batch review',
    (tester) async {
      final file1 = PickedDocument(
        name: 'cert1.pdf',
        mimeType: 'application/pdf',
        bytes: _validPngBytes,
      );
      final file2 = PickedDocument(
        name: 'award.jpg',
        mimeType: 'image/jpeg',
        bytes: _validPngBytes,
      );
      final service = _ScreenDocumentService();
      final picker = _FakePicker(file1, multiResult: [file1, file2]);

      await tester.pumpWidget(_app(service, AddFileScreen(filePicker: picker)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tap to upload file'));
      await tester.pumpAndSettle();

      expect(find.byType(BatchReviewScreen), findsOneWidget);
      expect(find.text('Upload All Valid'), findsOneWidget);

      service.disposeWithAuth();
    },
  );

  testWidgets(
    'explicit Add pages to this document adds a page to one logical document',
    (tester) async {
      final page1 = PickedDocument(
        name: 'page1.jpg',
        mimeType: 'image/jpeg',
        bytes: _validPngBytes,
      );
      final page2 = PickedDocument(
        name: 'page2.png',
        mimeType: 'image/png',
        bytes: _validPngBytes,
      );
      final service = _ScreenDocumentService();
      final picker = _FakePicker(page1);

      await tester.pumpWidget(_app(service, AddFileScreen(filePicker: picker)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add pages to one document'));
      await tester.pumpAndSettle();

      expect(find.text('Document Pages (1)'), findsOneWidget);
      expect(
        find.text('Pages will be saved together as one document.'),
        findsOneWidget,
      );

      picker.result = page2;
      await tester.ensureVisible(
        find.text('Add pages to this document (1/10)'),
      );
      await tester.tap(find.text('Add pages to this document (1/10)'));
      await tester.pumpAndSettle();

      expect(find.text('Document Pages (2)'), findsOneWidget);
      expect(find.text('page1.jpg'), findsOneWidget);
      expect(find.text('page2.png'), findsOneWidget);

      // Fill required fields and save as single document
      await tester.ensureVisible(find.byType(DropdownButton<String>).first);
      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Certificates').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Seminars').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        'Combined Multi-page Document',
      );
      await tester.tap(find.text('MM/DD/YYYY'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Add File'));
      await tester.tap(find.text('Add File'));
      await tester.pumpAndSettle();

      expect(service.uploadedFiles.length, 2);
      expect(service.uploadedFiles.map((f) => f.name).toList(), [
        'page1.jpg',
        'page2.png',
      ]);
      expect(service.uploadedTitle, 'Combined Multi-page Document');

      service.disposeWithAuth();
    },
  );

  testWidgets(
    'adding Page 2 while Page 1 OCR is active: no parallel request, no visible OCR_BUSY, stale Page 1 ignored, one automatic rerun',
    (tester) async {
      final page1 = PickedDocument(
        name: 'page1.jpg',
        mimeType: 'image/jpeg',
        bytes: _validPngBytes,
      );
      final page2 = PickedDocument(
        name: 'page2.jpg',
        mimeType: 'image/jpeg',
        bytes: _validPngBytes,
      );

      final comp1 = Completer<DocumentOcrResult>();
      final comp2 = Completer<DocumentOcrResult>();
      final service = _ScreenDocumentService()
        ..previewResponses.addAll([comp1.future, comp2.future]);
      final picker = _FakePicker(page1);

      await tester.pumpWidget(_app(service, AddFileScreen(filePicker: picker)));
      await tester.pumpAndSettle();

      // 1. Pick Page 1 -> starts OCR (comp1 is waiting)
      await tester.tap(find.text('Add pages to one document'));
      await tester.pump();
      expect(service.previewCalls, 1);
      expect(find.text('Reading document...'), findsOneWidget);

      // 2. While OCR is running, tap Add pages to this document
      picker.result = page2;
      await tester.ensureVisible(
        find.text('Add pages to this document (1/10)'),
      );
      await tester.tap(find.text('Add pages to this document (1/10)'));
      await tester.pump();

      // Must NOT launch a second parallel network request!
      expect(service.previewCalls, 1);
      expect(find.text('Document Pages (2)'), findsOneWidget);

      // 3. Complete Page 1 request with OCR_BUSY error (e.g. simulated server collision)
      comp1.completeError(
        const ApiException(code: 'OCR_BUSY', message: 'Server busy'),
      );
      await tester.pump();

      // User must NOT see OCR_BUSY because it was stale!
      expect(
        find.textContaining('busy processing another document'),
        findsNothing,
      );
      // Automatic rerun for pages 1+2 was triggered!
      expect(service.previewCalls, 2);

      // 4. Complete second OCR request with valid suggestions
      comp2.complete(
        DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          rawText: 'Combined Two Page Text',
          metadataSuggestions: DocumentMetadataSuggestions(
            title: 'Auto Title From Pages 1 and 2',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Title from rerun is applied; no further OCR calls
      expect(service.previewCalls, 2);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Auto Title From Pages 1 and 2',
      );

      service.disposeWithAuth();
    },
  );

  testWidgets(
    'page reorder during active OCR ignores stale result and reruns with final order',
    (tester) async {
      final page1 = PickedDocument(
        name: 'first.jpg',
        mimeType: 'image/jpeg',
        bytes: _validPngBytes,
      );
      final page2 = PickedDocument(
        name: 'second.jpg',
        mimeType: 'image/jpeg',
        bytes: _validPngBytes,
      );

      final comp1 = Completer<DocumentOcrResult>();
      final comp2 = Completer<DocumentOcrResult>();
      final service = _ScreenDocumentService()
        ..previewResponses.addAll([comp1.future, comp2.future]);

      // Start with 2 pages directly via initialFiles
      await tester.pumpWidget(
        _app(
          service,
          AddFileScreen(
            filePicker: _FakePicker(null),
            initialFiles: [page1, page2],
          ),
        ),
      );
      await tester.pump(); // comp1 in flight
      expect(service.previewCalls, 1);

      // Reorder: move Page 2 up to become Page 1 while comp1 is in flight
      await tester.ensureVisible(find.byTooltip('Move page up'));
      await tester.tap(find.byTooltip('Move page up'));
      await tester.pump();

      // Still only 1 in-flight call (no parallel duplicate)
      expect(service.previewCalls, 1);

      // Complete comp1 with stale old-order suggestion
      comp1.complete(
        DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          rawText: 'First then Second',
          metadataSuggestions: DocumentMetadataSuggestions(
            title: 'Stale Old Order Title',
          ),
        ),
      );
      await tester.pump();

      // Rerun automatically triggered with the reordered pages
      expect(service.previewCalls, 2);
      expect(service.previewFileBatches.last.map((f) => f.name).toList(), [
        'second.jpg',
        'first.jpg',
      ]);

      // Complete comp2 with new order suggestion
      comp2.complete(
        DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          rawText: 'Second then First',
          metadataSuggestions: DocumentMetadataSuggestions(
            title: 'Correct New Order Title',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Correct New Order Title',
      );

      service.disposeWithAuth();
    },
  );

  testWidgets(
    'page remove during active OCR ignores stale result and reruns with remaining pages',
    (tester) async {
      final page1 = PickedDocument(
        name: 'keep.jpg',
        mimeType: 'image/jpeg',
        bytes: _validPngBytes,
      );
      final page2 = PickedDocument(
        name: 'drop.jpg',
        mimeType: 'image/jpeg',
        bytes: _validPngBytes,
      );

      final comp1 = Completer<DocumentOcrResult>();
      final comp2 = Completer<DocumentOcrResult>();
      final service = _ScreenDocumentService()
        ..previewResponses.addAll([comp1.future, comp2.future]);

      await tester.pumpWidget(
        _app(
          service,
          AddFileScreen(
            filePicker: _FakePicker(null),
            initialFiles: [page1, page2],
          ),
        ),
      );
      await tester.pump(); // comp1 in flight
      expect(service.previewCalls, 1);

      // Remove Page 2 while comp1 is in flight
      await tester.ensureVisible(find.byTooltip('Remove page').last);
      await tester.tap(find.byTooltip('Remove page').last);
      await tester.pump();

      expect(service.previewCalls, 1);

      // Complete comp1 with stale result for 2 pages
      comp1.complete(
        DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          rawText: 'Both pages',
          metadataSuggestions: DocumentMetadataSuggestions(
            title: 'Two Pages Title',
          ),
        ),
      );
      await tester.pump();

      // Rerun triggered with only keep.jpg
      expect(service.previewCalls, 2);
      expect(service.previewFileBatches.last.map((f) => f.name).toList(), [
        'keep.jpg',
      ]);

      // Complete comp2
      comp2.complete(
        DocumentOcrResult(
          status: DocumentOcrStatus.ready,
          rawText: 'Single page',
          metadataSuggestions: DocumentMetadataSuggestions(
            title: 'Single Page Kept Title',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Single Page Kept Title',
      );

      service.disposeWithAuth();
    },
  );

  testWidgets(
    'manual metadata edits (Title, Date, Content, Folder) survive OCR rerun after adding page',
    (tester) async {
      final page1 = PickedDocument(
        name: 'manual_page1.jpg',
        mimeType: 'image/jpeg',
        bytes: _validPngBytes,
      );
      final page2 = PickedDocument(
        name: 'manual_page2.jpg',
        mimeType: 'image/jpeg',
        bytes: _validPngBytes,
      );

      final service = _ScreenDocumentService()
        ..previewResponses.addAll([
          Future.value(
            DocumentOcrResult(
              status: DocumentOcrStatus.ready,
              rawText: 'Page 1 initial text',
              metadataSuggestions: DocumentMetadataSuggestions(
                categoryKey: 'certificates',
                folderKey: 'seminars',
                title: 'Original OCR Title',
                documentDate: DateTime(2026, 1, 1),
              ),
            ),
          ),
          Future.value(
            DocumentOcrResult(
              status: DocumentOcrStatus.ready,
              rawText: 'Combined rerun text',
              metadataSuggestions: DocumentMetadataSuggestions(
                categoryKey: 'accomplishments',
                folderKey: 'projects',
                title: 'Overwriting Title Candidate',
                documentDate: DateTime(2025, 5, 5),
              ),
            ),
          ),
        ]);
      final picker = _FakePicker(page1);

      await tester.pumpWidget(_app(service, AddFileScreen(filePicker: picker)));
      await tester.pumpAndSettle();

      // 1. Pick Page 1
      await tester.tap(find.text('Add pages to one document'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Original OCR Title',
      );

      // 2. Manually override Title
      await tester.enterText(
        find.byType(TextField).first,
        'Protected Manual Title',
      );
      await tester.pumpAndSettle();

      // 3. Manually select Content: Accomplishments -> Folder: Projects
      await tester.ensureVisible(find.byType(DropdownButton<String>).first);
      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accomplishments').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Projects').last);
      await tester.pumpAndSettle();

      // 4. Manually select Date
      await tester.ensureVisible(find.byType(DatePickerField));
      await tester.tap(find.byType(DatePickerField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // 5. Add Page 2, which triggers OCR rerun suggesting different metadata
      picker.result = page2;
      await tester.ensureVisible(
        find.text('Add pages to this document (1/10)'),
      );
      await tester.tap(find.text('Add pages to this document (1/10)'));
      await tester.pumpAndSettle();

      // Verify manual edits were preserved and not overwritten by the rerun!
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Protected Manual Title',
      );
      expect(find.text('Accomplishments'), findsOneWidget);
      expect(find.text('Projects'), findsOneWidget);

      service.disposeWithAuth();
    },
  );
}

final _validPngBytes = Uint8List.fromList(const [
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

Widget _viewFiles() => const ViewFilesScreen(
  categoryKey: 'certificates',
  categoryName: 'Certificates',
  folderKey: 'seminars',
  folderName: 'Seminars',
);

DocumentOcrResult _suggestedOcr() => DocumentOcrResult(
  status: DocumentOcrStatus.ready,
  metadataSuggestions: DocumentMetadataSuggestions(
    categoryKey: 'certificates',
    folderKey: 'seminars',
    title: 'Digital Records Management',
    documentDate: DateTime(2026, 9, 14),
    description: 'Certificate of Completion for Digital Records Management.',
  ),
);

Future<_FakePicker> _openSuggestionForm(
  WidgetTester tester,
  DocumentService service, {
  bool settle = true,
}) async {
  final picker = _FakePicker(
    PickedDocument(
      name: 'demo.pdf',
      mimeType: 'application/pdf',
      bytes: Uint8List.fromList('%PDF-test'.codeUnits),
    ),
  );
  await tester.pumpWidget(_app(service, AddFileScreen(filePicker: picker)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Add pages to one document'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return picker;
}

Widget _app(DocumentService service, Widget child) => DocumentScope(
  documentService: service,
  child: MaterialApp(home: child),
);

Future<void> _completeUploadForm(
  WidgetTester tester, {
  bool pick = true,
}) async {
  if (pick) {
    await tester.tap(find.text('Add pages to one document'));
    await tester.pump();
  }

  await tester.ensureVisible(find.byType(DropdownButton<String>).first);
  await tester.tap(find.byType(DropdownButton<String>).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Certificates').last);
  await tester.pumpAndSettle();

  await tester.tap(find.byType(DropdownButton<String>).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Seminars').last);
  await tester.pumpAndSettle();

  await tester.ensureVisible(find.byType(TextField).first);
  await tester.enterText(find.byType(TextField).first, 'Demo Certificate');
  await tester.ensureVisible(find.text('MM/DD/YYYY'));
  await tester.tap(find.text('MM/DD/YYYY'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Add File'));
}

class _FakePicker implements DocumentPicker {
  _FakePicker(this.result, {this.multiResult});

  PickedDocument? result;
  List<PickedDocument>? multiResult;
  int calls = 0;

  @override
  Future<PickedDocument?> pickDocument() async {
    calls++;
    if (multiResult != null && multiResult!.isNotEmpty) {
      return multiResult!.first;
    }
    return result;
  }

  @override
  Future<List<PickedDocument>?> pickDocuments({
    bool allowMultiple = true,
  }) async {
    calls++;
    if (allowMultiple && multiResult != null) {
      return multiResult;
    }
    if (result != null) return [result!];
    if (multiResult != null && multiResult!.isNotEmpty) {
      return [multiResult!.first];
    }
    return null;
  }

  @override
  Future<PickedDocument?> pickFromCamera() async {
    calls++;
    return result;
  }

  @override
  Future<void> cleanCache() async {}
}

class _ScreenDocumentService extends DocumentService {
  factory _ScreenDocumentService({
    List<DocumentCategory>? categories,
    List<DocumentRecord> documents = const [],
    DocumentSummary summary = DocumentSummary.empty,
    ApiException? uploadFailure,
    DocumentOcrResult ocr = const DocumentOcrResult(
      status: DocumentOcrStatus.notProcessed,
    ),
    Completer<DocumentOcrResult>? extraction,
    ApiException? extractionFailure,
  }) {
    final auth = _NoopAuthService();
    return _ScreenDocumentService._(
      auth,
      categories: categories ?? _categories,
      documents: documents,
      summary: summary,
      uploadFailure: uploadFailure,
      ocr: ocr,
      extraction: extraction,
      extractionFailure: extractionFailure,
    );
  }

  _ScreenDocumentService._(
    this._auth, {
    required List<DocumentCategory> categories,
    required List<DocumentRecord> documents,
    required DocumentSummary summary,
    required this.uploadFailure,
    required DocumentOcrResult ocr,
    required this.extraction,
    required this.extractionFailure,
  }) : _activeCategories = categories,
       _documents = documents,
       _summary = summary,
       _ocr = ocr,
       super(authService: _auth);

  static const _categories = [
    DocumentCategory(
      key: 'certificates',
      name: 'Certificates',
      folders: [
        DocumentFolder(key: 'seminars', name: 'Seminars'),
        DocumentFolder(key: 'trainings', name: 'Trainings'),
      ],
    ),
    DocumentCategory(
      key: 'accomplishments',
      name: 'Accomplishments',
      folders: [DocumentFolder(key: 'projects', name: 'Projects')],
    ),
  ];

  final _NoopAuthService _auth;
  final List<DocumentCategory> _activeCategories;
  List<DocumentRecord> _documents;
  DocumentSummary _summary;
  final ApiException? uploadFailure;
  DocumentOcrResult _ocr;
  final Completer<DocumentOcrResult>? extraction;
  final ApiException? extractionFailure;
  int extractionCalls = 0;
  int previewCalls = 0;
  final List<Future<DocumentOcrResult>> previewResponses = [];
  final List<PickedDocument> previewFiles = [];
  final List<List<PickedDocument>> previewFileBatches = [];
  String? savedText;
  final List<String> deletedIds = [];
  PickedDocument? uploadedFile;
  List<PickedDocument> uploadedFiles = const [];
  String? uploadedCategoryKey;
  String? uploadedFolderKey;
  String? uploadedTitle;
  DateTime? uploadedDate;
  String? uploadedDescription;
  String? uploadedReflection;

  @override
  List<DocumentCategory> get categories => _activeCategories;

  @override
  List<DocumentRecord> get documents => List.unmodifiable(_documents);

  @override
  DocumentSummary get summary => _summary;

  @override
  bool get hasLoadedDocuments => true;

  @override
  bool get hasLoadedCategories => true;

  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => null;

  @override
  Future<void> load({bool force = false}) async {}

  @override
  Future<DocumentRecord> upload({
    String descriptionSource = 'unknown',
    PickedDocument? file,
    List<PickedDocument>? files,
    required String categoryKey,
    required String folderKey,
    required String title,
    required DateTime documentDate,
    String? description,
    String? reflection,
    ScholasticDetails? scholastic,
  }) async {
    final failure = uploadFailure;
    if (failure != null) throw failure;
    final effectiveFiles = files != null && files.isNotEmpty
        ? List<PickedDocument>.unmodifiable(files)
        : (file == null ? const <PickedDocument>[] : [file]);
    final effectiveFile = effectiveFiles.firstOrNull;
    uploadedFile = effectiveFile;
    uploadedFiles = effectiveFiles;
    uploadedCategoryKey = categoryKey;
    uploadedFolderKey = folderKey;
    uploadedTitle = title;
    uploadedDate = documentDate;
    uploadedDescription = description;
    uploadedReflection = reflection;
    final attachments = effectiveFiles.isEmpty
        ? null
        : [
            for (var i = 0; i < effectiveFiles.length; i++)
              DocumentAttachmentRecord(
                id: '${i + 1}',
                originalFileName: effectiveFiles[i].name,
                mimeType: effectiveFiles[i].mimeType,
                fileKind: effectiveFiles[i].mimeType == 'application/pdf'
                    ? 'pdf'
                    : 'image',
                extension: effectiveFiles[i].name.split('.').last.toLowerCase(),
                sizeBytes: effectiveFiles[i].sizeBytes,
                order: i,
              ),
          ];
    final created = _document(
      fileName: effectiveFile?.name ?? 'document.pdf',
      mimeType: effectiveFile?.mimeType ?? 'application/pdf',
      fileKind:
          effectiveFile?.mimeType == 'application/pdf' || effectiveFile == null
          ? 'pdf'
          : 'image',
      extension: effectiveFile?.name.split('.').last.toLowerCase() ?? 'pdf',
      attachments: attachments,
    );
    seedUploadedContent(created, effectiveFiles);
    _documents = [created, ..._documents];
    _summary = _summary.adding(created);
    notifyListeners();
    return created;
  }

  @override
  void seedDocumentOcr(String documentId, DocumentOcrResult ocr) {
    _ocr = ocr;
    super.seedDocumentOcr(documentId, ocr);
  }

  @override
  Future<void> delete(String documentId) async {
    deletedIds.add(documentId);
    final matches = _documents.where((value) => value.id == documentId);
    final existing = matches.isEmpty ? null : matches.first;
    _documents = _documents
        .where((value) => value.id != documentId)
        .toList(growable: false);
    if (existing != null) _summary = _summary.removing(existing);
    notifyListeners();
  }

  @override
  Future<DocumentOcrResult> loadOcr(String documentId) async =>
      ocrFor(documentId) ?? _ocr;

  @override
  Future<DocumentOcrResult> previewOcr(dynamic fileOrFiles) async {
    return _readingResult(fileOrFiles);
  }

  @override
  Future<CompiledAnalysisResult> analyzeCompiledDocument(
    PickedDocument file,
  ) async {
    return singlePdfAnalysis(file, await _readingResult(file));
  }

  @override
  Future<bool> cancelCompiledSession(String sessionId) async => true;

  // Count logical metadata reads for both image preview and PDF page analysis.
  Future<DocumentOcrResult> _readingResult(dynamic fileOrFiles) async {
    previewCalls++;
    final files = fileOrFiles is List<PickedDocument>
        ? fileOrFiles
        : fileOrFiles is PickedDocument
        ? [fileOrFiles]
        : const <PickedDocument>[];
    previewFiles.addAll(files);
    previewFileBatches.add(List<PickedDocument>.unmodifiable(files));
    if (previewResponses.isNotEmpty) return await previewResponses.removeAt(0);
    final failure = extractionFailure;
    if (failure != null) throw failure;
    return extraction == null ? _ocr : await extraction!.future;
  }

  @override
  Future<DocumentOcrResult> extractText(String documentId) async {
    extractionCalls++;
    final failure = extractionFailure;
    if (failure != null) {
      _ocr = const DocumentOcrResult(status: DocumentOcrStatus.failed);
      throw failure;
    }
    final result = extraction == null
        ? const DocumentOcrResult(
            status: DocumentOcrStatus.ready,
            rawText: 'Extracted test text',
            reviewedText: 'Extracted test text',
            engine: 'tesseract.js',
          )
        : await extraction!.future;
    _ocr = result;
    super.seedDocumentOcr(documentId, result);
    notifyListeners();
    return result;
  }

  @override
  Future<DocumentOcrResult> saveReviewedText(
    String documentId,
    String reviewedText,
  ) async {
    savedText = reviewedText;
    _ocr = DocumentOcrResult(
      status: DocumentOcrStatus.ready,
      rawText: _ocr.rawText,
      reviewedText: reviewedText,
      engine: _ocr.engine,
    );
    super.seedDocumentOcr(documentId, _ocr);
    notifyListeners();
    return _ocr;
  }

  void disposeWithAuth() {
    dispose();
    _auth.dispose();
  }
}

class _NoopAuthService extends AuthService {
  _NoopAuthService()
    : super(
        apiClient: ApiClient(baseUrl: 'http://example.test:3000'),
        tokenStore: _NoopTokenStore(),
      );
}

class _NoopTokenStore implements SecureTokenStore {
  @override
  Future<void> deleteRefreshToken() async {}

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> writeRefreshToken(String refreshToken) async {}
}

DocumentRecord _document({
  String fileName = 'certificate.pdf',
  String mimeType = 'application/pdf',
  String fileKind = 'pdf',
  String extension = 'pdf',
  List<DocumentAttachmentRecord>? attachments,
}) => DocumentRecord(
  id: 'document-1',
  categoryKey: 'certificates',
  folderKey: 'seminars',
  title: 'Certificate',
  documentDate: DateTime(2026, 9, 11),
  originalFileName: fileName,
  mimeType: mimeType,
  fileKind: fileKind,
  extension: extension,
  sizeBytes: 128,
  attachments: attachments,
  createdAt: DateTime(2026, 9, 11),
  updatedAt: DateTime(2026, 9, 11),
);
