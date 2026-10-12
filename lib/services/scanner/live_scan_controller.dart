import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'classical_cv_engine.dart';
import 'live_scan_geometry.dart';

typedef LiveFrameDetector = Future<DocumentDetection> Function(GrayscaleFrame);

/// Single-flight, latest-only CV scheduling plus conservative temporal tracking.
/// No camera frames, OCR, network work or full-size images are retained here.
class LiveScanController extends ChangeNotifier {
  LiveScanController({LiveFrameDetector? detector, int Function()? clock})
    : _detector = detector ?? _detect,
      _clock = clock ?? (Stopwatch()..start()).elapsedMillisecondsGetter;

  static Future<DocumentDetection> _detect(GrayscaleFrame frame) =>
      compute(ClassicalCvEngine.detectGrayscale, frame);

  final LiveFrameDetector _detector;
  final int Function() _clock;
  bool _disposed = false;
  bool _enabled = true;
  bool _busy = false;
  int _generation = 0;
  int _lastStarted = -100000;
  int _lastSeen = -100000;
  int lastProcessingMilliseconds = 0;
  int _consistent = 0;
  DocumentCorners? corners;
  DocumentCorners? _jump;
  ScanPreviewGeometry? geometry;
  bool stable = false;
  Timer? _expiry;

  // At most ~3 passes/s, slower when measured processing takes longer. Busy
  // frames are dropped before copying; there is never a pending-frame queue.
  int get intervalMilliseconds =>
      math.max(350, lastProcessingMilliseconds + 80);
  bool get canProcess =>
      !_disposed &&
      _enabled &&
      !_busy &&
      _clock() - _lastStarted >= intervalMilliseconds;

  void reset({bool enabled = true}) {
    if (_disposed) return;
    _generation++;
    _enabled = enabled;
    _lastStarted = -100000;
    geometry = null;
    _clear();
    notifyListeners();
  }

  void _clear() {
    _expiry?.cancel();
    _expiry = null;
    corners = null;
    stable = false;
    _consistent = 0;
    _jump = null;
  }

  Future<void> process(
    GrayscaleFrame frame,
    ScanPreviewGeometry transform,
  ) async {
    if (!canProcess) return;
    if (geometry != transform) {
      _generation++;
      _clear();
      geometry = transform;
    }
    final generation = _generation;
    final started = _clock();
    _lastStarted = started;
    _busy = true;
    try {
      final result = await _detector(frame);
      if (_disposed || generation != _generation || !_enabled) return;
      lastProcessingMilliseconds = math.max(0, _clock() - started);
      // A delayed result is not evidence of the CURRENT camera view.
      if (_clock() - started > 1400) {
        _clear();
      } else {
        _track(result, started);
      }
      notifyListeners();
    } catch (_) {
      if (!_disposed && generation == _generation) {
        _clear();
        notifyListeners();
      }
    } finally {
      _busy = false;
    }
  }

  static double _distance(DocumentCorners a, DocumentCorners b) {
    final ap = a.toList();
    final bp = b.toList();
    return List.generate(4, (i) => (ap[i] - bp[i]).distance).reduce(math.max);
  }

  void _track(DocumentDetection result, int capturedAt) {
    if (!result.isConfident || result.ambiguous) {
      // Ambiguity/disappearance is never green. Retain only a brief neutral
      // outline; the fixed last-seen deadline is NOT extended by misses.
      stable = false;
      _consistent = 0;
      _jump = null;
      if (result.ambiguous || _clock() - _lastSeen >= 1000) _clear();
      return;
    }
    final next = result.corners;
    final old = corners;
    if (old != null && _distance(old, next) > .12) {
      stable = false;
      _consistent = 0;
      if (_jump == null || _distance(_jump!, next) > .04) {
        _jump = next;
        return; // An isolated jump cannot move the outline.
      }
      corners = next; // A repeatedly observed new position is intentional.
    } else if (old != null) {
      _consistent = _distance(old, next) <= .035 ? _consistent + 1 : 1;
      corners = DocumentCorners.fromList(
        List.generate(
          4,
          (i) => Offset.lerp(old.toList()[i], next.toList()[i], .65)!,
        ),
      );
    } else {
      corners = next;
      _consistent = 1;
    }
    _jump = null;
    stable = _consistent >= 3;
    _lastSeen = capturedAt;
    _expiry?.cancel();
    _expiry = Timer(
      Duration(milliseconds: math.max(1, 1000 - (_clock() - capturedAt))),
      () {
        if (!_disposed) {
          _clear();
          notifyListeners();
        }
      },
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _clear();
    super.dispose();
  }
}

extension on Stopwatch {
  int elapsedMillisecondsGetter() => elapsedMilliseconds;
}
