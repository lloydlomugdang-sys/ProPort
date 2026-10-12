import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:proport_app/screens/files/document_scan_review_screen.dart';
import 'package:proport_app/screens/files/live_document_scanner_screen.dart';
import 'package:proport_app/services/document_picker.dart';
import 'package:proport_app/services/scanner/classical_cv_engine.dart';

import 'helpers/scanner_fixture.dart';
import 'helpers/fake_scanner_camera.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late File photo;
  late Uint8List original;
  String? acceptedPath;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() async {
    // Functional widget tests use a bundled stand-in font. Never fetch fonts
    // over HTTP, or change production typography just to run the test.
    final font = ByteData.sublistView(
      await File('assets/fonts/NotoSans-Regular.ttf').readAsBytes(),
    );
    final manifest = <String, Object>{
      for (final weight in ['Regular', 'Medium', 'SemiBold'])
        'test-fonts/Poppins-$weight.ttf': [
          {'asset': 'test-fonts/Poppins-$weight.ttf'},
        ],
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final key = utf8.decode(
            message!.buffer.asUint8List(
              message.offsetInBytes,
              message.lengthInBytes,
            ),
          );
          if (key == 'AssetManifest.bin') {
            return const StandardMessageCodec().encodeMessage(manifest);
          }
          if (key.startsWith('test-fonts/')) return font;
          return null;
        });
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    temp = await Directory.systemTemp.createTemp('gradport_scanner_review_');
    photo = File('${temp.path}/capture.jpg');
    original = scannerBytes(scannerPhoto(width: 240, height: 200));
    await photo.writeAsBytes(original);
    acceptedPath = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => temp.path);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    // Only the unique, test-created OS temporary directory is removed.
    await temp.delete(recursive: true);
  });

  Future<void> waitForPreview(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 150; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (find
            .byKey(const Key('scan-corrected-preview'))
            .evaluate()
            .isNotEmpty) {
          return;
        }
      }
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan-corrected-preview')), findsOneWidget);
  }

  Future<void> openReview(WidgetTester tester, DocumentCorners corners) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                acceptedPath = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => DocumentScanReviewScreen(
                      imagePath: photo.path,
                      initialCorners: corners,
                    ),
                  ),
                );
              },
              child: const Text('Open scanner'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open scanner'));
    await tester.pump();
    await waitForPreview(tester);
  }

  testWidgets(
    'live shutter opens existing corrected Review Scan; retake resumes camera',
    (tester) async {
      final first = FakeScannerCamera(path: photo.path);
      final second = FakeScannerCamera();
      var cameras = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LiveDocumentScannerScreen(
            cameraFactory: () => cameras++ == 0 ? first : second,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('live-scan-shutter')));
      await tester.pump();
      await waitForPreview(tester);
      expect(find.text('Review Scan'), findsOneWidget);
      expect(find.textContaining('Automatically cropped'), findsOneWidget);
      expect(first.closes, 1);
      final preview = tester.widget<Image>(
        find.byKey(const Key('scan-corrected-preview')),
      );
      expect(
        img.decodeJpg((preview.image as MemoryImage).bytes)!.width,
        lessThan(240),
      );
      await tester.tap(find.text('Retake'));
      await tester.runAsync(() async {
        for (var i = 0; i < 100 && second.starts == 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
      expect(second.starts, 1);
      expect(find.byKey(const Key('live-scan-shutter')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(second.closes, 1);
    },
  );

  testWidgets(
    'confident scan shows correction immediately and uploads exactly the reviewed JPEG',
    (tester) async {
      await openReview(tester, ClassicalCvEngine.detectCorners(original));
      expect(find.text('Review Scan'), findsOneWidget);
      expect(find.byKey(const Key('scan-corner-adjustment')), findsNothing);
      expect(find.textContaining('Automatically cropped'), findsOneWidget);
      final preview = tester.widget<Image>(
        find.byKey(const Key('scan-corrected-preview')),
      );
      final reviewed = (preview.image as MemoryImage).bytes;
      final decoded = img.decodeJpg(reviewed)!;
      expect(decoded.width, lessThan(240));
      expect(decoded.height, lessThan(200));
      await tester.tap(find.text('Use Scan'));
      await tester.runAsync(() async {
        for (var i = 0; i < 100 && acceptedPath == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
      expect(acceptedPath, isNotNull);
      await tester.runAsync(() async {
        expect(await File(acceptedPath!).readAsBytes(), reviewed);
        expect(await photo.readAsBytes(), original);
      });
    },
  );
  testWidgets(
    'uncertain detection ignores legacy inset and preserves full capture',
    (tester) async {
      await openReview(tester, DocumentCorners.defaultInset());
      expect(find.textContaining('Full photo kept'), findsOneWidget);
      expect(find.byKey(const Key('scan-corner-adjustment')), findsNothing);
      final preview = tester.widget<Image>(
        find.byKey(const Key('scan-corrected-preview')),
      );
      final decoded = img.decodeJpg((preview.image as MemoryImage).bytes)!;
      expect(decoded.width, 240);
      expect(decoded.height, 200);
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Use Scan'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'manual corners are optional, require a preview, and full-photo undo is available',
    (tester) async {
      await openReview(tester, ClassicalCvEngine.detectCorners(original));
      await tester.tap(find.text('Adjust corners'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('scan-corner-adjustment')), findsOneWidget);
      final viewport = tester.getRect(
        find.byKey(const Key('scan-corner-adjustment')),
      );
      final scale = math.min(viewport.width / 240, viewport.height / 200);
      final imageOrigin =
          viewport.center - Offset(240 * scale, 200 * scale) / 2;
      final corner = ClassicalCvEngine.detectCorners(original).topLeft;
      await tester.dragFrom(
        imageOrigin + Offset(corner.dx * 240 * scale, corner.dy * 200 * scale),
        const Offset(18, 18),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Manual adjustment'), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Use Scan'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Preview Scan'));
      await waitForPreview(tester);
      expect(find.byKey(const Key('scan-corner-adjustment')), findsNothing);
      await tester.tap(find.text('Use full photo'));
      await waitForPreview(tester);
      final preview = tester.widget<Image>(
        find.byKey(const Key('scan-corrected-preview')),
      );
      final decoded = img.decodeJpg((preview.image as MemoryImage).bytes)!;
      expect(decoded.width, 240);
      expect(decoded.height, 200);
    },
  );
  testWidgets(
    'enhancement changes the preview and retake never returns a scan',
    (tester) async {
      await openReview(tester, ClassicalCvEngine.detectCorners(original));
      await tester.tap(find.text('Grayscale'));
      await waitForPreview(tester);
      await tester.tap(find.text('Retake'));
      await tester.pumpAndSettle();
      expect(find.text('Open scanner'), findsOneWidget);
      expect(acceptedPath, isNull);
      await tester.runAsync(
        () async => expect(await photo.readAsBytes(), original),
      );
    },
  );
  test(
    'headless camera fallback retains the full image without changing capture',
    () async {
      original = scannerBytes(
        scannerPhoto(width: 240, height: 200, paper: 180, background: 180),
      );
      await photo.writeAsBytes(original);
      final picker = DeviceDocumentPicker(
        photoPicker:
            ({required source, maxWidth, maxHeight, imageQuality}) async {
              expect(source, ImageSource.camera);
              expect(maxWidth, 2400);
              expect(maxHeight, 2400);
              return XFile(photo.path);
            },
      );
      final result = await picker.pickFromCamera();
      expect(result, isNotNull);
      final decoded = img.decodeJpg(await result!.readBytes())!;
      expect(decoded.width, 240);
      expect(decoded.height, 200);
      expect(decoded.getPixel(0, 0).r, closeTo(180, 3));
      expect(await photo.readAsBytes(), original);
    },
  );
}
