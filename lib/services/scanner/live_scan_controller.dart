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
  bool _hysteresisUsed = false;
  Timer? _expiry;

  // Adaptive scheduling: at most one job at a time; target ~5 fps on fast
  // devices but slow down proportionally when processing takes longer.
  // Minimum floor is 120 ms (was 350 ms) to stay responsive on modern hardware
  // while still preventing runaway CPU on weak devices.
  int get intervalMilliseconds =>
      math.max(120, lastProcessingMilliseconds + 50);
  bool get canProcess =>
      !_disposed &&
      _enabled &&
      !_busy &&
      _clock() - _lastStarted >= intervalMilliseconds;

  /// Returns the current live corners mapped into upright oriented coordinates
  /// (matching EXIF-normalized still images) when tracking is stable, or null.
  DocumentCorners? get stableOrientedCorners {
    final c = corners;
    if (!stable || c == null || !c.isAutoDetected) return null;
    final g = geometry;
    if (g == null || (g.clockwiseQuarterTurns % 4 == 0 && !g.mirrored)) {
      return c;
    }
    final oriented = c.toList().map(g.orient).toList();
    return DocumentCorners.fromList(ClassicalCvEngine.orderCorners(oriented));
  }

  /// Debug/instrumentation counters (not logged in production).
  int debugDetectorCalls = 0;
  int debugLastCandidateScore = 0; // scaled 0..100
  int debugStabilizationCount = 0;

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
    _hysteresisUsed = false;
    _consistent = 0;
    _jump = null;
    debugStabilizationCount = 0;
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
      debugDetectorCalls++;
      final result = await _detector(frame);
      if (_disposed || generation != _generation || !_enabled) return;
      lastProcessingMilliseconds = math.max(0, _clock() - started);
      // A result older than 1400 ms is no longer evidence of the CURRENT view.
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
    debugLastCandidateScore = (result.confidence * 100).round();
    if (!result.isConfident || result.ambiguous) {
      // Ambiguity/disappearance is never green. Retain only a brief neutral
      // outline; the fixed last-seen deadline is NOT extended by misses.
      stable = false;
      _hysteresisUsed = false;
      _consistent = 0;
      _jump = null;
      if (result.ambiguous || _clock() - _lastSeen >= 1000) _clear();
      return;
    }
    final requiredConsistency =
        result.confidence >= 0.95 &&
            result.edgeSupport >= 0.90 &&
            result.weakestSideSupport >= 0.85
        ? 2
        : 3;
    final next = result.corners;
    final old = corners;
    if (old != null && _distance(old, next) > .12) {
      stable = false;
      _hysteresisUsed = false;
      _consistent = 0;
      if (_jump == null || _distance(_jump!, next) > .04) {
        _jump = next;
        return; // An isolated jump cannot move the outline.
      }
      corners = next; // A repeatedly observed new position is intentional.
      _consistent = 1;
    } else if (old != null) {
      final dist = _distance(old, next);
      if (dist <= .035) {
        _consistent = _consistent + 1;
        _hysteresisUsed = false;
        corners = DocumentCorners.fromList(
          List.generate(
            4,
            (i) => Offset.lerp(old.toList()[i], next.toList()[i], .65)!,
          ),
        );
      } else if (stable && !_hysteresisUsed && dist <= .08) {
        // Stable quad hysteresis: tolerate a single moderate-jitter frame
        // without dropping stable status, while blending conservatively.
        _hysteresisUsed = true;
        _consistent = requiredConsistency;
        corners = DocumentCorners.fromList(
          List.generate(
            4,
            (i) => Offset.lerp(old.toList()[i], next.toList()[i], .35)!,
          ),
        );
      } else {
        // Looser jitter while acquiring (or consecutive noisy frames) resets
        // to 1 confirmed observation rather than 0.
        _hysteresisUsed = false;
        _consistent = 1;
        corners = DocumentCorners.fromList(
          List.generate(
            4,
            (i) => Offset.lerp(old.toList()[i], next.toList()[i], .65)!,
          ),
        );
      }
    } else {
      corners = next;
      _hysteresisUsed = false;
      _consistent = 1;
    }
    _jump = null;
    debugStabilizationCount = _consistent;

    // Threshold for stability:
    // - Exceptionally strong detection (confidence >= 0.95, strong edges) + 2 frames → ready
    // - Normal/weak detections require 3 frames
    stable = _consistent >= requiredConsistency;

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
