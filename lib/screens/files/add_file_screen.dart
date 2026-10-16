// LOCATION: lib/screens/files/add_file_screen.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../services/api_client.dart';
import '../../services/document_models.dart';
import '../../services/document_picker.dart';
import '../../services/document_scope.dart';
import '../../services/document_service.dart';
import '../../widgets/grad_app_bar.dart';
import '../../widgets/primary_button.dart';
import 'batch_review_screen.dart';
import 'compiled_review_screen.dart';
import 'widgets/custom_dropdown.dart';
import 'widgets/date_picker_field.dart';
import 'widgets/optional_field.dart';
import 'widgets/upload_card.dart';

enum _OcrField { content, folder, title, date, description }

class AddFileScreen extends StatefulWidget {
  const AddFileScreen({super.key, this.filePicker, this.initialFiles});

  final DocumentPicker? filePicker;
  final List<PickedDocument>? initialFiles;

  @override
  State<AddFileScreen> createState() => _AddFileScreenState();
}

class _AddFileScreenState extends State<AddFileScreen>
    with SingleTickerProviderStateMixin {
  // ─── Upload state ─────────────────────────────────────────────────────────
  List<PickedDocument> _pickedFiles = const [];
  PickedDocument? get _pickedFile =>
      _pickedFiles.isNotEmpty ? _pickedFiles.first : null;
  late final DocumentPicker _filePicker;
  DocumentService? _documentService;
  PickedDocument? _analyzedPdf;
  CompiledAnalysisResult? _pdfAnalysis;

  // ─── Form state ───────────────────────────────────────────────────────────
  String? _selectedContent;
  String? _selectedFolder;
  DateTime? _selectedDate;
  bool _descriptionEnabled = false;
  bool _reflectionEnabled = false;

  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _reflectionCtrl = TextEditingController();

  bool _isSubmitting = false;
  bool _isSuggesting = false;
  bool _rerunQueued = false;
  DocumentOcrResult? _lastPreviewOcr;
  final Map<PickedDocument, DocumentOcrPage> _pageOcrByFile = {};
  DocumentMetadataSuggestions? _suggestions;
  String? _suggestionMessage;
  int _previewOperation = 0;
  final Set<_OcrField> _automaticFields = {};
  final Set<_OcrField> _manualFields = {};
  bool _hasEditedAiSuggestion = false;
  bool _writingSuggestions = false;
  bool _suggestionFailed = false;
  bool _suggestedByAi = false;
  String _observedTitle = '';
  String _observedDescription = '';

  // ─── Entrance animation ───────────────────────────────────────────────────
  late final AnimationController _entranceCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _filePicker = widget.filePicker ?? DeviceDocumentPicker();
    if (widget.initialFiles != null && widget.initialFiles!.isNotEmpty) {
      _pickedFiles = List.from(widget.initialFiles!);
    }
    _titleCtrl.addListener(() {
      if (_titleCtrl.text == _observedTitle) return;
      _observedTitle = _titleCtrl.text;
      if (!_writingSuggestions) {
        setState(() => _markManual(_OcrField.title));
      }
    });
    _descriptionCtrl.addListener(() {
      if (_descriptionCtrl.text == _observedDescription) return;
      _observedDescription = _descriptionCtrl.text;
      if (!_writingSuggestions) {
        setState(() => _markManual(_OcrField.description));
      }
    });
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceCtrl,
            curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
          ),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _entranceCtrl.forward();
      DocumentScope.of(context).load().catchError((_) {});
      if (_pickedFiles.isNotEmpty) {
        _validateAndSuggestInitialFiles();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _documentService = DocumentScope.of(context);
    // Categories can finish loading after the OCR response. Apply matching keys
    // then as well, without letting a category-list failure discard useful text.
    final operation = _previewOperation;
    if (_suggestions != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && operation == _previewOperation) _applySuggestions();
      });
    }
  }

  @override
  void dispose() {
    _previewOperation++;
    final analysis = _pdfAnalysis;
    if (analysis != null) {
      unawaited(_documentService?.cancelCompiledSession(analysis.sessionId));
    }
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _reflectionCtrl.dispose();
    _entranceCtrl.dispose();
    super.dispose();
  }

  // ─── Folder options derived from selected content type ────────────────────
  DocumentCategory? _selectedCategory(List<DocumentCategory> categories) {
    for (final category in categories) {
      if (category.name == _selectedContent) return category;
    }
    return null;
  }

  List<String> _folderOptions(List<DocumentCategory> categories) =>
      _selectedCategory(
        categories,
      )?.folders.map((folder) => folder.name).toList() ??
      const [];

  // ─── Initial files validation + OCR schedule ─────────────────────────────
  Future<void> _validateAndSuggestInitialFiles() async {
    if (!mounted || _isSubmitting || _isSuggesting) return;
    final file = _pickedFile;
    if (file == null) return;
    if (!file.hasSupportedUploadType) {
      _showSnack(
        file.mimeType.startsWith('image/')
            ? 'Please capture a JPG, JPEG, or PNG image.'
            : 'Please select a PDF, JPG, JPEG, or PNG file.',
      );
      if (mounted) setState(() => _pickedFiles = const []);
      return;
    }
    if (file.sizeBytes > DocumentService.maxUploadBytes) {
      _showSnack(
        file.mimeType.startsWith('image/')
            ? 'The captured photo exceeds the 15 MB upload limit.'
            : 'The selected file exceeds the 15 MB upload limit.',
      );
      if (mounted) setState(() => _pickedFiles = const []);
      return;
    }
    await _suggestDetails();
  }

  // ─── Upload handler ───────────────────────────────────────────────────────
  Future<void> _onUploadTap({bool oneDocument = false}) async {
    if (_isSubmitting) return;
    try {
      final selected = await _filePicker.pickDocuments(allowMultiple: true);
      if (selected == null || selected.isEmpty || !mounted) return;

      if (selected.length > 20) {
        _showSnack(
          'You can select up to 20 documents. Selected: ${selected.length}.',
        );
        return;
      }

      if (oneDocument) {
        if (selected.length > 10 ||
            (selected.length > 1 &&
                selected.any((f) => f.mimeType == 'application/pdf'))) {
          _showSnack('Choose up to 10 images for one document, or one PDF.');
          return;
        }
        if (selected.any(
              (f) =>
                  !f.hasSupportedUploadType ||
                  f.sizeBytes > DocumentService.maxUploadBytes,
            ) ||
            selected.fold<int>(0, (sum, f) => sum + f.sizeBytes) >
                45 * 1024 * 1024) {
          _showSnack(
            'Choose supported files up to 15 MB each and 45 MB combined.',
          );
          return;
        }
        setState(() {
          _clearAutomaticFields();
          _pickedFiles = List.of(selected);
          _lastPreviewOcr = null;
          _pageOcrByFile.clear();
          _previewOperation++;
          _isSuggesting = false;
          _rerunQueued = false;
          _suggestions = null;
          _suggestionMessage = null;
          _suggestionFailed = false;
          _suggestedByAi = false;
          _hasEditedAiSuggestion = false;
        });
        unawaited(_suggestDetails());
      } else {
        _previewOperation++;
        _rerunQueued = false;
        final service = DocumentScope.of(context);
        final result = await BatchReviewScreen.open(context, selected);

        if (result == true && mounted) {
          await service.load(force: true);
          if (mounted) Navigator.pop(context, true);
        }
      }
    } on ApiException catch (error) {
      if (mounted) _showSnack(error.message);
    } catch (_) {
      if (!mounted) return;
      _showSnack('Unable to read the selected file. Please try another file.');
    }
  }

  Future<void> _onAddPageTap() async {
    if (_isSubmitting) return;
    if (_pickedFiles.length >= 10) {
      _showSnack('You can attach up to 10 image pages.');
      return;
    }
    try {
      final selected = await _filePicker.pickDocuments(allowMultiple: true);
      if (selected == null || selected.isEmpty || !mounted) return;
      final validNewPages = <PickedDocument>[];
      for (final newPage in selected) {
        if (!newPage.hasSupportedUploadType ||
            !newPage.mimeType.startsWith('image/')) {
          _showSnack('Please select a JPG, JPEG, or PNG image page.');
          return;
        }
        if (newPage.sizeBytes > DocumentService.maxUploadBytes) {
          _showSnack('${newPage.name} exceeds the 15 MB upload limit.');
          return;
        }
        validNewPages.add(newPage);
      }
      if (_pickedFiles.length + validNewPages.length > 10) {
        _showSnack('You can attach up to 10 image pages.');
        return;
      }
      final currentBytes = _pickedFiles.fold(0, (sum, f) => sum + f.sizeBytes);
      final newBytes = validNewPages.fold(0, (sum, f) => sum + f.sizeBytes);
      if (currentBytes + newBytes > 45 * 1024 * 1024) {
        _showSnack('The combined files exceed the 45 MB upload limit.');
        return;
      }
      setState(() {
        _pickedFiles = [..._pickedFiles, ...validNewPages];
      });
      unawaited(_suggestDetails());
    } catch (_) {
      if (!mounted) return;
      _showSnack('Unable to read the page image. Please try another file.');
    }
  }

  Future<void> _onCameraCaptureTap() async {
    if (_isSubmitting) return;
    try {
      final photo = await _filePicker.pickFromCamera();
      if (photo == null || !mounted) return;

      if (!photo.hasSupportedUploadType) {
        _showSnack('Please capture a JPG, JPEG, or PNG image.');
        return;
      }
      if (photo.sizeBytes > DocumentService.maxUploadBytes) {
        _showSnack('The captured photo exceeds the 15 MB upload limit.');
        return;
      }

      setState(() {
        _clearAutomaticFields();
        _pickedFiles = [photo];
        _lastPreviewOcr = null;
        _pageOcrByFile.clear();
        _previewOperation++;
        _isSuggesting = false;
        _suggestions = null;
        _suggestionMessage = null;
        _suggestionFailed = false;
        _suggestedByAi = false;
        _hasEditedAiSuggestion = false;
      });
      await _suggestDetails();
    } catch (e) {
      if (!mounted) return;
      final errStr = e.toString().toLowerCase();
      final msg = errStr.contains('permission') || errStr.contains('denied')
          ? 'Camera permission was denied. Please allow camera access in device settings.'
          : 'Unable to scan document. Please try again.';
      _showSnack(msg);
    }
  }

  Future<void> _onPickCompiledPortfolioTap() async {
    if (_isSubmitting || _isSuggesting) return;
    try {
      final selected = await _filePicker.pickDocuments(allowMultiple: false);
      if (selected == null || selected.isEmpty || !mounted) return;
      final file = selected.first;
      if (file.mimeType != 'application/pdf') {
        _showSnack('Compiled document separation requires a PDF file.');
        return;
      }
      if (file.sizeBytes > DocumentService.maxUploadBytes) {
        _showSnack('The selected file exceeds the 15 MB upload limit.');
        return;
      }
      await _startCompiledSeparation(file);
    } catch (_) {
      if (!mounted) return;
      _showSnack('Unable to read the selected file. Please try again.');
    }
  }

  Future<void> _startCompiledSeparation(PickedDocument file) async {
    await _inspectPdf(file, forceReview: true);
  }

  Future<void> _inspectPdf(
    PickedDocument file, {
    bool forceReview = false,
  }) async {
    if (_isSuggesting || _isSubmitting) return;
    final service = DocumentScope.of(context);
    final operation = ++_previewOperation;
    setState(() => _isSuggesting = true);
    try {
      var analysis = identical(file, _analyzedPdf) ? _pdfAnalysis : null;
      if (analysis == null) {
        final prior = _pdfAnalysis;
        _pdfAnalysis = null;
        if (prior != null) await service.cancelCompiledSession(prior.sessionId);
        analysis = await service.analyzeCompiledDocument(file);
      }
      if (!mounted || operation != _previewOperation) {
        await service.cancelCompiledSession(analysis.sessionId);
        return;
      }
      _pdfAnalysis = analysis;
      _analyzedPdf = file;
      setState(() {
        _isSuggesting = false;
        _suggestionFailed = false;
      });
      final canNavigateAutomatically =
          _manualFields.isEmpty && _reflectionCtrl.text.trim().isEmpty;
      final isMultiDocument =
          analysis.documents.length > 1 || analysis.detection == 'multiple';
      if (forceReview ||
          (canNavigateAutomatically &&
              (isMultiDocument || analysis.hasUnresolvedPages))) {
        await service.load();
        if (!mounted || operation != _previewOperation) return;
        // Categories may finish loading after the user starts editing.
        if (!forceReview &&
            (_manualFields.isNotEmpty ||
                _reflectionCtrl.text.trim().isNotEmpty)) {
          setState(
            () => _suggestionMessage =
                'PDF analysis is ready. Your edits are preserved; use Separate to review.',
          );
          return;
        }
        final splitSuccess = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (ctx) => DocumentScope(
              documentService: service,
              child: CompiledReviewScreen(analysis: analysis!, file: file),
            ),
          ),
        );
        _pdfAnalysis =
            null; // The review owns cancellation/success for this session.
        if (splitSuccess == true && mounted) {
          if (mounted) Navigator.pop(context, true);
        }
        return;
      }
      final proposal = analysis.documents.length == 1
          ? analysis.documents.first
          : null;
      if (analysis.metadataSuggestions != null) {
        _showMetadataSuggestions(
          analysis.metadataSuggestions,
          analysis.metadataAnalysis,
        );
        _applySuggestions();
        return;
      }
      setState(() {
        _suggestionMessage = analysis!.hasUnresolvedPages
            ? 'Some pages are unreadable. Use Separate to review and retry.'
            : isMultiDocument
            ? 'Multiple documents detected. Your edits are preserved; use Separate to review.'
            : 'PDF pages analyzed. Review the suggested details before saving.';
        if (proposal != null) {
          _suggestions = DocumentMetadataSuggestions(
            categoryKey: proposal.categoryKey.isEmpty
                ? null
                : proposal.categoryKey,
            folderKey: proposal.folderKey.isEmpty ? null : proposal.folderKey,
            title: proposal.confidence > 0 ? proposal.title : null,
            documentDate: proposal.documentDate,
            confidence: proposal.confidence >= 0.75 ? 'high' : 'low',
          );
        }
      });
      _applySuggestions();
    } on ApiException catch (e) {
      if (mounted && operation == _previewOperation) {
        setState(() {
          _suggestionFailed = true;
          _suggestionMessage = _readingFailure(e);
        });
      }
    } catch (_) {
      if (mounted && operation == _previewOperation) {
        setState(() {
          _suggestionFailed = true;
          _suggestionMessage =
              'PDF analysis failed. Retry, or enter details manually.';
        });
      }
    } finally {
      if (mounted && operation == _previewOperation) {
        setState(() => _isSuggesting = false);
      }
    }
  }

  void _movePageUp(int index) {
    if (index <= 0 || _isSubmitting) return;
    setState(() {
      final list = List<PickedDocument>.from(_pickedFiles);
      final item = list.removeAt(index);
      list.insert(index - 1, item);
      _pickedFiles = list;
      _rebuildPreviewOcrForCurrentOrder();
    });
    unawaited(_suggestDetails());
  }

  void _movePageDown(int index) {
    if (index >= _pickedFiles.length - 1 || _isSubmitting) return;
    setState(() {
      final list = List<PickedDocument>.from(_pickedFiles);
      final item = list.removeAt(index);
      list.insert(index + 1, item);
      _pickedFiles = list;
      _rebuildPreviewOcrForCurrentOrder();
    });
    unawaited(_suggestDetails());
  }

  void _removePage(int index) {
    if (_isSubmitting) return;
    var hasRemaining = false;
    setState(() {
      final list = List<PickedDocument>.from(_pickedFiles);
      final removed = list.removeAt(index);
      _pageOcrByFile.remove(removed);
      _pickedFiles = list;
      if (_pickedFiles.isEmpty) {
        _clearAutomaticFields();
        _lastPreviewOcr = null;
        _pageOcrByFile.clear();
        _suggestions = null;
        _suggestionMessage = null;
      } else {
        hasRemaining = true;
        _rebuildPreviewOcrForCurrentOrder();
      }
    });
    if (hasRemaining) {
      unawaited(_suggestDetails());
    } else {
      _previewOperation++;
      if (_isSuggesting) {
        setState(() {
          _isSuggesting = false;
          _rerunQueued = false;
        });
      }
    }
  }

  void _recordPreviewOcr(List<PickedDocument> files, DocumentOcrResult result) {
    if (result.pages.isNotEmpty) {
      for (var i = 0; i < files.length && i < result.pages.length; i++) {
        _pageOcrByFile[files[i]] = result.pages[i];
      }
      return;
    }
    if (files.length == 1) {
      _pageOcrByFile[files.first] = DocumentOcrPage(
        pageNumber: 1,
        status: 'ready',
        originalFileName: files.first.name,
        mimeType: files.first.mimeType,
        rawText: result.rawText,
      );
      return;
    }
    final raw = result.rawText;
    if (raw == null || raw.isEmpty) return;
    final matches = RegExp(
      r'---\s*Page\s+(\d+)\s*---\r?\n([\s\S]*?)(?=\r?\n\r?\n---\s*Page\s+\d+\s*---|$)',
    ).allMatches(raw);
    for (final match in matches) {
      final pageNum = int.tryParse(match.group(1) ?? '');
      final text = match.group(2)?.trim();
      if (pageNum != null &&
          pageNum >= 1 &&
          pageNum <= files.length &&
          text != null) {
        final file = files[pageNum - 1];
        _pageOcrByFile[file] = DocumentOcrPage(
          pageNumber: pageNum,
          status: text.isNotEmpty ? 'ready' : 'failed',
          originalFileName: file.name,
          mimeType: file.mimeType,
          rawText: text,
        );
      }
    }
  }

  void _rebuildPreviewOcrForCurrentOrder() {
    if (_pickedFiles.isEmpty || _lastPreviewOcr == null) return;
    final rebuiltPages = <DocumentOcrPage>[];
    final chunks = <String>[];
    for (var i = 0; i < _pickedFiles.length; i++) {
      final file = _pickedFiles[i];
      final cached = _pageOcrByFile[file];
      if (cached == null) continue;
      rebuiltPages.add(
        DocumentOcrPage(
          pageNumber: i + 1,
          status: cached.status,
          originalFileName: file.name,
          mimeType: file.mimeType,
          rawText: cached.rawText,
        ),
      );
      final text = cached.rawText?.trim() ?? '';
      if (!cached.isFailed && text.isNotEmpty) {
        chunks.add(
          _pickedFiles.length > 1 ? '--- Page ${i + 1} ---\n$text' : text,
        );
      }
    }
    if (chunks.isEmpty) return;
    final combined = chunks.join('\n\n');
    final now = DateTime.now().toUtc();
    _lastPreviewOcr = DocumentOcrResult(
      status: DocumentOcrStatus.ready,
      rawText: combined,
      reviewedText: combined,
      engine: _lastPreviewOcr!.engine ?? 'tesseract.js',
      processedAt: _lastPreviewOcr!.processedAt ?? now,
      updatedAt: now,
      pages: rebuiltPages,
      metadataSuggestions: _lastPreviewOcr!.metadataSuggestions,
      metadataAnalysis: _lastPreviewOcr!.metadataAnalysis,
    );
  }

  // ─── Validation + submit ──────────────────────────────────────────────────
  Future<void> _onAddFile() async {
    if (_isSubmitting) return;
    if (_pickedFiles.isEmpty) {
      _showSnack('Please select a PDF, JPG, JPEG, or PNG file.');
      return;
    }
    final service = DocumentScope.of(context);
    final category = _selectedCategory(service.categories);
    if (_selectedContent == null) {
      _showSnack('Please select a Content Type.');
      return;
    }
    if (category == null) {
      _showSnack('The selected Content Type is unavailable.');
      return;
    }
    if (_selectedFolder == null) {
      _showSnack('Please select a Folder.');
      return;
    }
    DocumentFolder? folder;
    for (final candidate in category.folders) {
      if (candidate.name == _selectedFolder) folder = candidate;
    }
    if (folder == null) {
      _showSnack('The selected Folder is unavailable.');
      return;
    }
    if (_titleCtrl.text.trim().isEmpty) {
      _showSnack('Title is required.');
      return;
    }
    if (_titleCtrl.text.trim().length > 200) {
      _showSnack('Title cannot exceed 200 characters.');
      return;
    }
    if (_selectedDate == null) {
      _showSnack('Date is required.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _isSuggesting = false;
    });
    _previewOperation++;
    try {
      final filesSnapshot = List<PickedDocument>.from(_pickedFiles);
      final uploaded = await service.upload(
        file: _pickedFile,
        files: filesSnapshot,
        categoryKey: category.key,
        folderKey: folder.key,
        title: _titleCtrl.text.trim(),
        documentDate: _selectedDate!,
        description: _descriptionEnabled ? _descriptionCtrl.text : null,
        reflection: _reflectionEnabled ? _reflectionCtrl.text : null,
      );
      await service.seedUploadedContent(uploaded, filesSnapshot);
      _rebuildPreviewOcrForCurrentOrder();
      if (_lastPreviewOcr != null && _lastPreviewOcr!.isReady) {
        service.seedDocumentOcr(uploaded.id, _lastPreviewOcr!);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'File uploaded successfully.',
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          duration: const Duration(seconds: 3),
        ),
      );
      unawaited(_filePicker.cleanCache());
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      final msg = switch (error.statusCode) {
        413 => 'The file exceeds the upload size limit.',
        429 => 'Too many upload attempts. Please wait a moment and try again.',
        401 => 'Your session has expired. Please log in again.',
        403 => 'You do not have permission to upload this document.',
        _ =>
          error.message.isNotEmpty
              ? error.message
              : 'Unable to upload the file. Please try again.',
      };
      _showSnack(msg);
    } catch (_) {
      _showSnack('Unable to upload the file. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _suggestDetails() async {
    if (_pickedFiles.isEmpty || _isSubmitting) return;
    if (_pickedFiles.length == 1 &&
        _pickedFiles.first.mimeType == 'application/pdf') {
      if (_isSuggesting) return;
      await _inspectPdf(_pickedFiles.first);
      return;
    }

    // If OCR is already running, mark current in-flight request stale and queue exactly one rerun.
    if (_isSuggesting) {
      _rerunQueued = true;
      _previewOperation++;
      return;
    }

    _isSuggesting = true;
    _rerunQueued = false;

    try {
      while (mounted && !_isSubmitting && _pickedFiles.isNotEmpty) {
        if (_pickedFiles.first.mimeType == 'application/pdf') {
          break;
        }

        final operation = ++_previewOperation;
        final filesSnapshot = List<PickedDocument>.from(_pickedFiles);
        final service = DocumentScope.of(context);

        setState(() {
          _isSuggesting = true;
          _suggestionMessage = null;
          _suggestionFailed = false;
        });

        try {
          final result = await service.previewOcr(filesSnapshot);
          if (!mounted || operation != _previewOperation) {
            // Result is stale or widget unmounted — safely ignored
          } else {
            if (!result.isReady) {
              throw const ApiException(
                code: 'OCR_FAILED',
                message: 'Automatic reading failed.',
              );
            }
            _recordPreviewOcr(filesSnapshot, result);
            _lastPreviewOcr = result;
            final suggestions = result.isReady
                ? result.metadataSuggestions
                : null;
            _showMetadataSuggestions(
              suggestions,
              result.metadataAnalysis,
              failedPageNumbers: result.failedPageNumbers,
            );
            if (suggestions != null) _applySuggestions();
          }
        } on ApiException catch (error) {
          if (mounted && operation == _previewOperation) {
            setState(() {
              _suggestionFailed = true;
              _suggestionMessage = _readingFailure(error);
            });
          }
        } catch (_) {
          if (mounted && operation == _previewOperation) {
            setState(() {
              _suggestionFailed = true;
              _suggestionMessage =
                  "We couldn't automatically read this file. You can still enter the details manually.";
            });
          }
        }

        if (!mounted || _isSubmitting) break;

        // If pages changed or another rerun was requested while in flight, rerun once
        if (_rerunQueued || !listEquals(filesSnapshot, _pickedFiles)) {
          _rerunQueued = false;
          continue;
        }

        break;
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSuggesting = false;
          _rerunQueued = false;
        });
      }
    }
  }

  String _readingFailure(ApiException error) => switch (error.code) {
    'NETWORK_ERROR' || 'NETWORK_OFFLINE' =>
      'No connection for automatic reading. You can still enter the details manually.',
    'NETWORK_TIMEOUT' =>
      'Automatic reading took too long. You can still enter the details manually.',
    'COLD_START_TIMEOUT' =>
      'The server is waking up and took too long to respond. Please retry in a moment, or enter the details manually.',
    'OCR_TIMEOUT' =>
      'Automatic reading timed out while processing this file. Please retry, or enter the details manually.',
    'OCR_BUSY' =>
      'The server is busy processing another document. Please retry shortly, or enter the details manually.',
    'RATE_LIMITED' =>
      'Too many reading requests. Please wait before retrying, or enter the details manually.',
    _ =>
      "We couldn't automatically read this file. You can still enter the details manually.",
  };

  void _showMetadataSuggestions(
    DocumentMetadataSuggestions? suggestions,
    DocumentMetadataAnalysis? analysis, {
    List<int> failedPageNumbers = const [],
  }) {
    setState(() {
      _suggestions = suggestions;
      _suggestedByAi = analysis?.source == 'gemini';
      var message = suggestions == null || suggestions.isEmpty
          ? 'No reliable details found. You can enter them manually.'
          : 'Suggested from OCR — review before adding your file.';
      if (_suggestedByAi) {
        message = 'AI suggested from document — review and edit before saving.';
      } else if (analysis?.aiStatus == 'unavailable') {
        message = suggestions == null || suggestions.isEmpty
            ? 'AI suggestions are temporarily unavailable. You can enter the details manually.'
            : 'AI suggestions are temporarily unavailable. Basic document details were applied where possible.';
      }
      if (failedPageNumbers.isNotEmpty) {
        final label = failedPageNumbers.length == 1
            ? 'Page ${failedPageNumbers.first}'
            : 'Pages ${failedPageNumbers.join(', ')}';
        message =
            '$label could not be read automatically. Readable pages were used; you can retry or continue.';
      }
      _suggestionMessage = message;
    });
  }

  void _markManual(_OcrField field) {
    if (_suggestedByAi && _automaticFields.contains(field)) {
      _hasEditedAiSuggestion = true;
    }
    _automaticFields.remove(field);
    _manualFields.add(field);
  }

  void _clearAutomaticFields() {
    _writingSuggestions = true;
    try {
      if (_automaticFields.contains(_OcrField.content)) _selectedContent = null;
      if (_automaticFields.contains(_OcrField.folder)) _selectedFolder = null;
      if (_automaticFields.contains(_OcrField.title)) _titleCtrl.clear();
      if (_automaticFields.contains(_OcrField.date)) _selectedDate = null;
      if (_automaticFields.contains(_OcrField.description)) {
        _descriptionCtrl.clear();
        _descriptionEnabled = false;
      }
      _automaticFields.clear();
    } finally {
      _writingSuggestions = false;
    }
  }

  void _applySuggestions({bool replace = false}) {
    final suggestions = _suggestions;
    if (suggestions == null || _isSubmitting) return;
    final categories = DocumentScope.of(context).categories;
    _writingSuggestions = true;
    try {
      setState(() {
        final suggestedCategory = categories
            .where((category) => category.key == suggestions.categoryKey)
            .firstOrNull;
        if (suggestedCategory != null &&
            (replace ||
                (!_manualFields.contains(_OcrField.content) &&
                    (_selectedContent == null ||
                        _automaticFields.contains(_OcrField.content))))) {
          if (_selectedContent != suggestedCategory.name) {
            if (!_manualFields.contains(_OcrField.folder)) {
              _selectedFolder = null;
            }
          }
          _selectedContent = suggestedCategory.name;
          _automaticFields.add(_OcrField.content);
        }
        final category = _selectedCategory(categories);
        if (category != null &&
            category.key == suggestions.categoryKey &&
            (replace ||
                (!_manualFields.contains(_OcrField.folder) &&
                    (_selectedFolder == null ||
                        _automaticFields.contains(_OcrField.folder))))) {
          final folder = category.folders
              .where((folder) => folder.key == suggestions.folderKey)
              .firstOrNull;
          if (folder != null) {
            _selectedFolder = folder.name;
            _automaticFields.add(_OcrField.folder);
          }
        }
        if (suggestions.title != null &&
            (replace ||
                (!_manualFields.contains(_OcrField.title) &&
                    (_titleCtrl.text.trim().isEmpty ||
                        _automaticFields.contains(_OcrField.title))))) {
          _titleCtrl.text = suggestions.title!;
          _automaticFields.add(_OcrField.title);
        }
        if (suggestions.documentDate != null &&
            (replace ||
                (!_manualFields.contains(_OcrField.date) &&
                    (_selectedDate == null ||
                        _automaticFields.contains(_OcrField.date))))) {
          _selectedDate = suggestions.documentDate;
          _automaticFields.add(_OcrField.date);
        }
        if (suggestions.description != null &&
            (replace ||
                (!_manualFields.contains(_OcrField.description) &&
                    (_descriptionCtrl.text.trim().isEmpty ||
                        _automaticFields.contains(_OcrField.description))))) {
          _descriptionCtrl.text = suggestions.description!;
          _descriptionEnabled = true;
          _automaticFields.add(_OcrField.description);
        }
        if (replace) {
          _manualFields.removeAll(_automaticFields);
          _hasEditedAiSuggestion = false;
        }
      });
    } finally {
      _writingSuggestions = false;
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final service = DocumentScope.of(context);
    final categoryNames = service.categories
        .map((category) => category.name)
        .toList();
    final folderOptions = _folderOptions(service.categories);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const GradBackAppBar(title: 'Add a File'),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Section 1: Upload ─────────────────────────────
                Text('1. Upload file', style: AppTextStyles.h4),
                const SizedBox(height: 10),
                UploadCard(
                  // Replacing pages within the explicit one-document workflow
                  // keeps that intent; ordinary selection always opens review.
                  onTap: () =>
                      _onUploadTap(oneDocument: _pickedFiles.isNotEmpty),
                  fileName: _pickedFiles.isEmpty
                      ? null
                      : _pickedFiles.length == 1
                      ? _pickedFiles.first.name
                      : '${_pickedFiles.first.name} (+${_pickedFiles.length - 1} pages)',
                  pageCount: _pickedFiles.length,
                ),
                TextButton.icon(
                  onPressed: _isSubmitting
                      ? null
                      : () => _onUploadTap(oneDocument: true),
                  icon: const Icon(Icons.collections_rounded),
                  label: const Text('Add pages to one document'),
                ),

                if (_pickedFiles.isEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _onCameraCaptureTap,
                          icon: const Icon(Icons.camera_alt_rounded, size: 18),
                          label: Text(
                            'Scan Camera',
                            style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(
                              color: AppColors.primary,
                              width: 1.2,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _onPickCompiledPortfolioTap,
                          icon: const Icon(Icons.splitscreen_rounded, size: 18),
                          label: Text(
                            'Split Portfolio',
                            style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(
                              color: AppColors.primary,
                              width: 1.2,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                if (_pickedFiles.length == 1 &&
                    _pickedFiles.first.mimeType == 'application/pdf') ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.auto_awesome,
                            size: 20,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Compiled Portfolio?',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                'Auto-separate individual documents in this PDF',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: _isSuggesting || _isSubmitting
                              ? null
                              : () => _startCompiledSeparation(
                                  _pickedFiles.first,
                                ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            'Separate',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (_pickedFiles.isNotEmpty &&
                    !_pickedFiles.any(
                      (f) => f.mimeType == 'application/pdf',
                    )) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Document Pages (${_pickedFiles.length})',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Max 10 pages',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Pages will be saved together as one document.',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                        if (_pickedFiles.length > 1) ...[
                          const SizedBox(height: 8),
                          for (var i = 0; i < _pickedFiles.length; i++)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Page ${i + 1}',
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _pickedFiles[i].name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  if (i > 0)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.arrow_upward,
                                        size: 16,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _movePageUp(i),
                                      tooltip: 'Move page up',
                                    ),
                                  if (i < _pickedFiles.length - 1)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.arrow_downward,
                                        size: 16,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _movePageDown(i),
                                      tooltip: 'Move page down',
                                    ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Colors.red,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _removePage(i),
                                    tooltip: 'Remove page',
                                  ),
                                ],
                              ),
                            ),
                        ],
                        if (_pickedFiles.length < 10) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            key: const Key('add-pages-to-document-button'),
                            onPressed: _onAddPageTap,
                            icon: const Icon(
                              Icons.add_photo_alternate_rounded,
                              size: 16,
                            ),
                            label: Text(
                              'Add pages to this document (${_pickedFiles.length}/10)',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(
                                color: AppColors.cardBorder,
                                width: 1.2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                if (_pickedFiles.isNotEmpty) ...[
                  if (_isSuggesting)
                    const Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('Reading document...'),
                      ],
                    ),
                  if (_suggestionFailed ||
                      (!_isSuggesting &&
                          (_lastPreviewOcr?.hasFailedPages ?? false)))
                    TextButton.icon(
                      onPressed: _isSubmitting ? null : _suggestDetails,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retry automatic reading'),
                    ),
                  if (_suggestionMessage != null)
                    Text(
                      _suggestionMessage!,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  if (_suggestions != null &&
                      !_suggestions!.isEmpty &&
                      (!_suggestedByAi || _hasEditedAiSuggestion))
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => _applySuggestions(replace: true),
                      child: Text(
                        _suggestedByAi
                            ? 'Reapply AI suggestions'
                            : 'Apply OCR suggestions',
                      ),
                    ),
                ],

                const SizedBox(height: 24),

                // ── Section 2: Details ────────────────────────────
                Text('2. Add Details', style: AppTextStyles.h4),
                const SizedBox(height: 12),

                // Content* dropdown
                CustomDropdown(
                  label: 'Content',
                  hint: 'Select content',
                  items: categoryNames,
                  value: _selectedContent,
                  required: true,
                  onChanged: (val) {
                    setState(() {
                      _selectedContent = val;
                      _selectedFolder = null; // reset folder
                      _markManual(_OcrField.content);
                      _markManual(_OcrField.folder);
                    });
                  },
                ),
                const SizedBox(height: 14),

                // Folder* dropdown — options depend on content selection
                CustomDropdown(
                  label: 'Folder',
                  hint: 'Select a folder',
                  items: folderOptions,
                  value: _selectedFolder,
                  required: true,
                  enabled: _selectedContent != null,
                  onChanged: (val) => setState(() {
                    _selectedFolder = val;
                    _markManual(_OcrField.folder);
                    // Keep the category that owns a manually selected folder.
                    _markManual(_OcrField.content);
                  }),
                ),
                const SizedBox(height: 14),

                // Title*
                _buildTextField(
                  label: 'Title',
                  hint: 'Enter title',
                  controller: _titleCtrl,
                  required: true,
                  maxLength: 200,
                ),
                const SizedBox(height: 14),

                // Date*
                DatePickerField(
                  label: 'Date',
                  selectedDate: _selectedDate,
                  required: true,
                  onDateSelected: (d) => setState(() {
                    _selectedDate = d;
                    _markManual(_OcrField.date);
                  }),
                ),
                const SizedBox(height: 14),

                // Description (optional)
                OptionalField(
                  label: 'Description',
                  hint: 'Enter description',
                  controller: _descriptionCtrl,
                  isEnabled: _descriptionEnabled,
                  onToggle: () => setState(() {
                    _descriptionEnabled = !_descriptionEnabled;
                    _markManual(_OcrField.description);
                  }),
                ),
                const SizedBox(height: 14),

                // Reflection (optional)
                OptionalField(
                  label: 'Reflection',
                  hint: 'Enter reflection',
                  controller: _reflectionCtrl,
                  isEnabled: _reflectionEnabled,
                  onToggle: () =>
                      setState(() => _reflectionEnabled = !_reflectionEnabled),
                ),

                const SizedBox(height: 28),

                // ── Add File button ───────────────────────────────
                PrimaryButton(
                  label: 'Add File',
                  icon: Icons.add_rounded,
                  onPressed: _onAddFile,
                  isLoading: _isSubmitting,
                  height: 52,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    bool required = false,
    int maxLines = 1,
    int? maxLength,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            if (required)
              Text(
                '*',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.danger,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            maxLength: maxLength,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: hint,
              counterText: '',
              hintStyle: GoogleFonts.poppins(
                fontSize: 14,
                color: AppColors.textMuted,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }
}
