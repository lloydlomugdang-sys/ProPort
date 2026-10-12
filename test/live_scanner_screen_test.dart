import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart' show CameraException;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:proport_app/screens/files/live_document_scanner_screen.dart';
import 'package:proport_app/services/document_picker.dart';
import 'package:proport_app/services/scanner/classical_cv_engine.dart';
import 'package:proport_app/services/scanner/live_scan_controller.dart';
import 'package:proport_app/services/scanner/live_scan_geometry.dart';

import 'helpers/fake_scanner_camera.dart';
import 'helpers/scanner_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('gradport_live_scan_test_');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  Future<void> until(WidgetTester tester, bool Function() condition) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 150 && !condition(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    expect(condition(), isTrue);
    await tester.pump(const Duration(milliseconds: 400));
  }

  for (final confident in [true, false]) {
    testWidgets(
      'captured still independently refines crop: confident=$confident',
      (tester) async {
        late File photo;
        late File accepted;
        await tester.runAsync(() async {
          photo = File('${temp.path}/capture.jpg');
          accepted = File('${temp.path}/scan_accepted.jpg');
          final bytes = confident
              ? scannerBytes(scannerPhoto(width: 320, height: 240))
              : scannerBytes(
                  img.Image(width: 320, height: 240)
                    ..clear(img.ColorRgb8(240, 240, 240)),
                );
          await photo.writeAsBytes(bytes);
          await accepted.writeAsBytes(bytes);
        });
        final camera = FakeScannerCamera(path: photo.path);
        DocumentCorners? reviewCorners;
        String? finalResult;
        var now = 0;
        final live = LiveScanController(
          clock: () => now,
          detector: (_) async => const DocumentDetection(
            corners: DocumentCorners(
              topLeft: Offset(.1, .1),
              topRight: Offset(.9, .1),
              bottomRight: Offset(.9, .9),
              bottomLeft: Offset(.1, .9),
            ),
            confidence: .9,
            edgeSupport: .9,
            weakestSideSupport: .9,
            areaFraction: .64,
            ambiguous: false,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  finalResult = await Navigator.of(context).push<String>(
                    MaterialPageRoute(
                      builder: (_) => LiveDocumentScannerScreen(
                        cameraFactory: () => camera,
                        liveController: live,
                        reviewBuilder: (path, corners) {
                          reviewCorners = corners;
                          return Scaffold(
                            body: TextButton(
                              onPressed: () =>
                                  Navigator.of(context).pop(accepted.path),
                              child: const Text('Accept review'),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('fake-camera-preview')), findsOneWidget);
        if (confident) {
          for (var i = 0; i < 3; i++) {
            await live.process(
              GrayscaleFrame(Uint8List(10000), 100, 100),
              const ScanPreviewGeometry(frameSize: Size(480, 640)),
            );
            now += 350;
          }
          await tester.pump();
          expect(find.text('Document ready • Tap to capture'), findsOneWidget);
        }
        await tester.tap(find.byKey(const Key('live-scan-shutter')));
        await tester.tap(find.byKey(const Key('live-scan-shutter')));
        await tester.pump();
        await until(tester, () => reviewCorners != null);
        expect(camera.captures, 1);
        expect(camera.stops, 1);
        expect(camera.closes, 1);
        expect(reviewCorners!.isAutoDetected, confident);
        if (!confident) expect(reviewCorners, DocumentCorners.fullImage());
        await tester.tap(find.text('Accept review'));
        await until(tester, () => finalResult != null);
        expect(finalResult, accepted.path);
        await tester.runAsync(() async {
          expect(await accepted.exists(), isTrue);
          expect(await photo.exists(), isFalse);
        });
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }

  testWidgets('permission failure has safe retry and cancel', (tester) async {
    final failed = FakeScannerCamera(
      error: CameraException('CameraAccessDenied', 'provider details'),
    );
    final good = FakeScannerCamera();
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LiveDocumentScannerScreen(
          cameraFactory: () => attempts++ == 0 ? failed : good,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Allow GradPort'), findsOneWidget);
    expect(find.textContaining('provider details'), findsNothing);
    expect(failed.closes, 1);
    await tester.tap(find.text('Retry camera'));
    await tester.pumpAndSettle();
    expect(good.starts, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(good.closes, 1);
  });

  testWidgets('capture failure closes the old camera and permits retry', (
    tester,
  ) async {
    final capture = Completer<String>();
    final failed = FakeScannerCamera(captureResult: capture);
    final next = FakeScannerCamera();
    var instances = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LiveDocumentScannerScreen(
          cameraFactory: () => instances++ == 0 ? failed : next,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('live-scan-shutter')));
    await tester.pump();
    capture.completeError(StateError('simulated camera failure'));
    await tester.pumpAndSettle();
    expect(failed.closes, 1);
    expect(next.starts, 1);
    expect(
      find.text('Could not capture the document. Please try again.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('live-scan-shutter')))
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(next.closes, 1);
  });

  testWidgets(
    'production picker opens GradPort scanner route and cancel returns null',
    (tester) async {
      var completed = false;
      Object? result = 'pending';
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: DeviceDocumentPicker.navigatorKey,
          home: Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await DeviceDocumentPicker().pickFromCamera();
                completed = true;
              },
              child: const Text('Scan'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();
      // On this hardware-independent host, the real adapter safely reports an
      // unsupported camera. It must still use OUR route, not ImagePicker UI.
      expect(find.byType(LiveDocumentScannerScreen), findsOneWidget);
      await tester.tap(find.byKey(const Key('live-scan-close')));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(result, isNull);
    },
  );

  testWidgets('background closes stream and resume creates a fresh camera', (
    tester,
  ) async {
    final first = FakeScannerCamera();
    final second = FakeScannerCamera();
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LiveDocumentScannerScreen(
          cameraFactory: () => attempts++ == 0 ? first : second,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(first.wantsFrame!(), isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(first.closes, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(second.starts, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(second.closes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'disposal during initialization closes late camera without UI updates',
    (tester) async {
      final pending = Completer<void>();
      final camera = FakeScannerCamera(initialization: pending);
      await tester.pumpWidget(
        MaterialApp(
          home: LiveDocumentScannerScreen(cameraFactory: () => camera),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      pending.complete();
      await tester.pump();
      expect(camera.closes, 1);
      expect(camera.starts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disposal ignores a late frame detection result', (tester) async {
    final pending = Completer<DocumentDetection>();
    final live = LiveScanController(detector: (_) => pending.future);
    final camera = FakeScannerCamera();
    await tester.pumpWidget(
      MaterialApp(
        home: LiveDocumentScannerScreen(
          cameraFactory: () => camera,
          liveController: live,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final processing = live.process(
      GrayscaleFrame(Uint8List(10000), 100, 100),
      const ScanPreviewGeometry(frameSize: Size(100, 100)),
    );
    await tester.pumpWidget(const SizedBox());
    pending.complete(
      DocumentDetection(
        corners: DocumentCorners.fullImage(),
        confidence: 0,
        edgeSupport: 0,
        weakestSideSupport: 0,
        areaFraction: 0,
        ambiguous: false,
      ),
    );
    await processing;
    await tester.pump();
    expect(camera.closes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late capture after background cannot open review', (
    tester,
  ) async {
    final pending = Completer<String>();
    final camera = FakeScannerCamera(captureResult: pending);
    var reviews = 0;
    late File photo;
    await tester.runAsync(() async {
      photo = await File(
        '${temp.path}/interrupted.jpg',
      ).writeAsBytes([1, 2, 3]);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: LiveDocumentScannerScreen(
          cameraFactory: () => camera,
          reviewBuilder: (_, _) {
            reviews++;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('live-scan-shutter')));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    pending.complete(photo.path);
    await until(tester, () => camera.closes == 1);
    expect(reviews, 0);
    await tester.pumpWidget(const SizedBox());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });

  test(
    'picker returns accepted live JPEG lazily and preserves cancellation',
    () async {
      final file = await File(
        '${temp.path}/accepted.jpg',
      ).writeAsBytes([1, 2, 3]);
      final picker = DeviceDocumentPicker(
        liveScannerRunner: () async => file.path,
      );
      final picked = await picker.pickFromCamera();
      expect(picked!.path, file.path);
      expect(picked.mimeType, 'image/jpeg');
      expect(picked.sizeBytes, 3);
      expect(
        await DeviceDocumentPicker(
          liveScannerRunner: () async => null,
        ).pickFromCamera(),
        isNull,
      );
    },
  );
}
