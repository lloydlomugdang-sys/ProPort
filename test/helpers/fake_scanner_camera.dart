import 'dart:async';

import 'package:flutter/material.dart';
import 'package:proport_app/services/scanner/scanner_camera.dart';

/// Exercises Dart lifecycle orchestration, not physical-camera functionality.
class FakeScannerCamera extends ScannerCamera {
  FakeScannerCamera({
    this.path = '',
    this.initialization,
    this.captureResult,
    this.error,
  });
  final String path;
  final Completer<void>? initialization;
  final Completer<String>? captureResult;
  final Object? error;
  int starts = 0;
  int stops = 0;
  int captures = 0;
  int closes = 0;
  bool Function()? wantsFrame;
  ScanFrameCallback? onFrame;

  @override
  Size get previewSize => const Size(480, 640);
  @override
  Object get orientationKey => 'portrait';
  @override
  Widget buildPreview() =>
      const ColoredBox(key: Key('fake-camera-preview'), color: Colors.grey);
  @override
  Future<void> initialize() async {
    if (initialization != null) await initialization!.future;
    if (error != null) throw error!;
  }

  @override
  Future<void> startFrames(
    bool Function() wantsFrame,
    ScanFrameCallback onFrame,
  ) async {
    starts++;
    this.wantsFrame = wantsFrame;
    this.onFrame = onFrame;
  }

  @override
  Future<void> stopFrames() async {
    stops++;
  }

  @override
  Future<String> capture() async {
    captures++;
    return captureResult == null ? path : captureResult!.future;
  }

  @override
  Future<void> close() async {
    closes++;
    wantsFrame = null;
    onFrame = null;
  }
}
