import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'classical_cv_engine.dart';
import 'live_scan_geometry.dart';

typedef ScanFrameCallback = void Function(GrayscaleFrame, ScanPreviewGeometry);

/// Hardware boundary, injectable in widget tests. One instance is used for one
/// foreground camera session, then closed before review/background/navigation.
abstract class ScannerCamera extends ChangeNotifier {
  Future<void> initialize();
  Size get previewSize;
  Object get orientationKey;
  String? get guidance => null;
  Widget buildPreview();
  Future<void> startFrames(
    bool Function() wantsFrame,
    ScanFrameCallback onFrame,
  );
  Future<void> stopFrames();
  Future<String> capture();
  Future<void> close();
}

int sensorQuarterTurns(int sensorDegrees, DeviceOrientation orientation) {
  final deviceDegrees = switch (orientation) {
    DeviceOrientation.portraitUp => 0,
    DeviceOrientation.landscapeLeft => 90,
    DeviceOrientation.portraitDown => 180,
    DeviceOrientation.landscapeRight => 270,
  };
  return ((sensorDegrees - deviceDegrees + 360) % 360) ~/ 90;
}

class DeviceScannerCamera extends ScannerCamera {
  CameraController? _controller;
  bool _closed = false;
  String? _guidance;
  @override
  String? get guidance => _guidance;

  void _setGuidance(String? value) {
    if (_guidance == value || _closed) return;
    _guidance = value;
    notifyListeners();
  }

  DeviceOrientation get _orientation => _controller!.value.deviceOrientation;

  @override
  Object get orientationKey => _orientation;

  @override
  Size get previewSize {
    final size = _controller!.value.previewSize!;
    final portrait =
        _orientation == DeviceOrientation.portraitUp ||
        _orientation == DeviceOrientation.portraitDown;
    return portrait ? Size(size.height, size.width) : size;
  }

  @override
  Future<void> initialize() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw CameraException('Unsupported', 'Use an Android or iOS device.');
    }
    final cameras = await availableCameras();
    final rear = cameras
        .where((c) => c.lensDirection == CameraLensDirection.back)
        .firstOrNull;
    if (rear == null) throw CameraException('NoRearCamera', 'No rear camera.');
    // This phase deliberately uses only the unmirrored rear camera. A front
    // camera is not silently substituted with an incorrect mirrored overlay.
    final controller = CameraController(
      rear,
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );
    _controller = controller;
    await controller.initialize();
    controller.addListener(_changed);
  }

  void _changed() {
    if (!_closed) notifyListeners();
  }

  @override
  Widget buildPreview() => CameraPreview(_controller!);

  @override
  Future<void> startFrames(
    bool Function() wantsFrame,
    ScanFrameCallback onFrame,
  ) => _controller!.startImageStream((image) {
    if (_closed || !wantsFrame() || image.planes.isEmpty) return;
    final bgra = image.format.group == ImageFormatGroup.bgra8888;
    if (!bgra &&
        image.format.group != ImageFormatGroup.yuv420 &&
        image.format.group != ImageFormatGroup.nv21) {
      _setGuidance('Live outline unavailable • Capture to detect and review');
      return;
    }
    // CameraX streams sensor-native pixels, whereas AVFoundation rotates
    // its video output buffer AND texture together before streaming.
    final geometry = ScanPreviewGeometry(
      frameSize: Size(image.width.toDouble(), image.height.toDouble()),
      clockwiseQuarterTurns: Platform.isIOS
          ? 0
          : sensorQuarterTurns(
              _controller!.description.sensorOrientation,
              _orientation,
            ),
    );
    if (!geometry.matchesPreview(previewSize)) {
      _setGuidance('Live outline unavailable • Capture to detect and review');
      return;
    }
    try {
      final plane = image.planes.first;
      final gray = sampleCameraLuminance(
        bytes: plane.bytes,
        width: image.width,
        height: image.height,
        bytesPerRow: plane.bytesPerRow,
        bytesPerPixel: plane.bytesPerPixel ?? (bgra ? 4 : 1),
        bgra: bgra,
      );
      _setGuidance(null);
      onFrame(gray, geometry);
    } on FormatException {
      // Unrecognized hardware layout: manual shutter + still CV remain
      // available. Never guess a layout and draw a misleading outline.
      _setGuidance('Live outline unavailable • Capture to detect and review');
    }
  });

  @override
  Future<void> stopFrames() async {
    if (_controller?.value.isStreamingImages ?? false) {
      await _controller!.stopImageStream();
    }
  }

  @override
  Future<String> capture() async => (await _controller!.takePicture()).path;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final controller = _controller;
    try {
      if (controller != null) {
        controller.removeListener(_changed);
        try {
          await stopFrames();
        } finally {
          await controller.dispose();
        }
      }
    } finally {
      _controller = null;
      super.dispose();
    }
  }
}
