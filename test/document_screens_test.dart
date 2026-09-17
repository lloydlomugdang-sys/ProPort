import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/screens/files/add_file_screen.dart';
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

      await tester.enterText(
        find.byKey(const Key('ocr-reviewed-text')),
        'Corrected certificate text',
      );
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(service.savedText, 'Corrected certificate text');
      expect(find.text('Text changes saved.'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pumpAndSettle();
      await tester.tap(find.text('certificate.pdf'));
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
        "We couldn't automatically read this file. You can still enter the details manually.",
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
        await tester.tap(find.text('Tap to upload file'));
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
}

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
  await tester.tap(find.text('Tap to upload file'));
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
    await tester.tap(find.text('Tap to upload file'));
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
  _FakePicker(this.result);

  PickedDocument? result;
  int calls = 0;

  @override
  Future<PickedDocument?> pickDocument() async {
    calls++;
    return result;
  }

  @override
  Future<List<PickedDocument>?> pickDocuments({
    bool allowMultiple = true,
  }) async {
    final single = await pickDocument();
    return single == null ? null : [single];
  }

  @override
  Future<PickedDocument?> pickFromCamera() async {
    calls++;
    return result;
  }
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
  String? savedText;
  final List<String> deletedIds = [];
  PickedDocument? uploadedFile;
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
    PickedDocument? file,
    List<PickedDocument>? files,
    required String categoryKey,
    required String folderKey,
    required String title,
    required DateTime documentDate,
    String? description,
    String? reflection,
  }) async {
    final failure = uploadFailure;
    if (failure != null) throw failure;
    final effectiveFile = file ?? files?.firstOrNull;
    uploadedFile = effectiveFile;
    uploadedCategoryKey = categoryKey;
    uploadedFolderKey = folderKey;
    uploadedTitle = title;
    uploadedDate = documentDate;
    uploadedDescription = description;
    uploadedReflection = reflection;
    final created = _document(fileName: effectiveFile?.name ?? 'document.pdf');
    _documents = [created, ..._documents];
    _summary = _summary.adding(created);
    notifyListeners();
    return created;
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
  Future<DocumentOcrResult> loadOcr(String documentId) async => _ocr;

  @override
  Future<DocumentOcrResult> previewOcr(dynamic fileOrFiles) async {
    previewCalls++;
    final files = fileOrFiles is List<PickedDocument>
        ? fileOrFiles
        : fileOrFiles is PickedDocument
        ? [fileOrFiles]
        : const <PickedDocument>[];
    previewFiles.addAll(files);
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

DocumentRecord _document({String fileName = 'certificate.pdf'}) =>
    DocumentRecord(
      id: 'document-1',
      categoryKey: 'certificates',
      folderKey: 'seminars',
      title: 'Certificate',
      documentDate: DateTime(2026, 9, 11),
      originalFileName: fileName,
      mimeType: 'application/pdf',
      fileKind: 'pdf',
      extension: 'pdf',
      sizeBytes: 128,
      createdAt: DateTime(2026, 9, 11),
      updatedAt: DateTime(2026, 9, 11),
    );
