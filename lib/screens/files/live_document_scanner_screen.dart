import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart' show CameraException;
import 'package:flutter/material.dart';

import '../../services/scanner/classical_cv_engine.dart';
import '../../services/scanner/live_scan_controller.dart';
import '../../services/scanner/live_scan_geometry.dart';
import '../../services/scanner/scanner_camera.dart';
import 'document_scan_review_screen.dart';

typedef ScanReviewBuilder =
    Widget Function(String path, DocumentCorners corners);

class LiveDocumentScannerScreen extends StatefulWidget {
  const LiveDocumentScannerScreen({
    super.key,
    this.cameraFactory,
    this.liveController,
    this.reviewBuilder,
  });
  final ScannerCamera Function()? cameraFactory;
  final LiveScanController? liveController;
  final ScanReviewBuilder? reviewBuilder;

  @override
  State<LiveDocumentScannerScreen> createState() =>
      _LiveDocumentScannerScreenState();
}

class _LiveDocumentScannerScreenState extends State<LiveDocumentScannerScreen>
    with WidgetsBindingObserver {
  late final LiveScanController _live;
  ScannerCamera? _camera;
  // All native operations (including close during init/capture) are serialized.
  Future<void> _operations = Future<void>.value();
  bool _active = true;
  bool _capturing = false;
  bool _reviewing = false;
  bool _leaving = false;
  bool _ready = false;
  int _epoch = 0;
  Object? _orientation;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _active = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _live = widget.liveController ?? LiveScanController();
    _enqueue(_start);
  }

  void _enqueue(Future<void> Function() action) {
    _operations = _operations.then((_) => action()).catchError((Object _) {
      if (mounted && !_leaving) {
        setState(() {
          _ready = false;
          _error = 'Camera unavailable. Please try again.';
        });
      }
    });
  }

  bool get _wantsCamera => mounted && _active && !_reviewing && !_leaving;

  Future<void> _start() async {
    if (!_wantsCamera || _camera != null) return;
    final epoch = _epoch;
    final camera = widget.cameraFactory?.call() ?? DeviceScannerCamera();
    _camera = camera;
    try {
      await camera.initialize();
      if (!_wantsCamera || epoch != _epoch) {
        await _closeCamera();
        return;
      }
      _orientation = camera.orientationKey;
      camera.addListener(_cameraChanged);
      _live.reset();
      await camera.startFrames(
        () => _wantsCamera && !_capturing && _live.canProcess,
        (frame, geometry) {
          unawaited(_live.process(frame, geometry));
        },
      );
      if (!_wantsCamera || epoch != _epoch) {
        await _closeCamera();
        return;
      }
      setState(() {
        _ready = true;
        _error = null;
      });
    } catch (error) {
      await _closeCamera();
      if (mounted && _active && !_leaving) {
        setState(() {
          _error =
              error is CameraException && error.code.startsWith('CameraAccess')
              ? 'Camera access is required. Allow GradPort to use the camera in Settings, then retry.'
              : 'Camera unavailable. Use an Android or iOS device with a rear camera, or try again.';
        });
      }
    }
  }

  void _cameraChanged() {
    if (!mounted || !_ready || _camera == null) return;
    if (_orientation != _camera!.orientationKey) {
      _orientation = _camera!.orientationKey;
      _live.reset(enabled: !_capturing && _active);
    }
    if (_camera!.guidance != null) _live.reset(enabled: !_capturing && _active);
    setState(() {});
  }

  Future<void> _closeCamera() async {
    final camera = _camera;
    _camera = null;
    _ready = false;
    if (camera != null) {
      camera.removeListener(_cameraChanged);
      await camera.close();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (!_active) {
      _epoch++;
      _live.reset(enabled: false);
      if (mounted) {
        setState(() {
          _ready = false;
        });
      }
      _enqueue(_closeCamera);
    } else if (!_reviewing) {
      _enqueue(_start);
    }
  }

  void _capture() {
    if (!_ready || _capturing || !_wantsCamera) return;
    final epoch = _epoch;
    // Snapshot the last stable live quad (mapped to upright orientation)
    // BEFORE resetting the controller.
    final liveHint = _live.stableOrientedCorners;
    setState(() {
      _capturing = true;
      _error = null;
    });
    _live.reset(enabled: false);
    _enqueue(() async {
      String? path;
      try {
        final camera = _camera;
        if (camera == null || epoch != _epoch) return;
        await camera.stopFrames();
        path = await camera.capture();
        await _closeCamera();
        if (!_wantsCamera || epoch != _epoch) return;
        // Refine independently from the full still (EXIF normalized, bounded
        // detection, normalized corners back to source resolution). A preview
        // frame is NEVER the OCR source or the authority for the final crop.
        final corners = await ClassicalCvEngine.detectCornersWithHintAsync(
          await File(path).readAsBytes(),
          liveHint: liveHint,
        );
        if (!mounted || !_wantsCamera || epoch != _epoch) return;
        _reviewing = true;
        final accepted = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) =>
                widget.reviewBuilder?.call(path!, corners) ??
                DocumentScanReviewScreen(
                  imagePath: path!,
                  initialCorners: corners,
                ),
          ),
        );
        _reviewing = false;
        if (!mounted || _leaving) return;
        if (accepted != null) {
          _leaving = true;
          Navigator.of(context).pop(accepted);
        }
      } catch (_) {
        await _closeCamera();
        if (mounted && !_leaving) {
          setState(() {
            _error = 'Could not capture the document. Please try again.';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not capture the document. Please try again.',
              ),
            ),
          );
        }
      } finally {
        // Only this session's camera-created temporary source is removed. The
        // independently written, accepted Review Scan JPEG stays available.
        if (path != null) {
          try {
            await File(path).delete();
          } catch (_) {
            /* OS cache can reclaim it. */
          }
        }
        _capturing = false;
        if (mounted && !_leaving) {
          setState(() {});
          await _start(); // Retake, or resume after interrupted capture.
        }
      }
    });
  }

  void _leave() {
    _leaving = true;
    _epoch++;
    _live.reset(enabled: false);
    _enqueue(_closeCamera);
  }

  @override
  void dispose() {
    _leaving = true;
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    _live.dispose();
    _enqueue(_closeCamera);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) _leave();
    },
    child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_ready && _camera != null)
            ClipRect(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = _camera!.previewSize;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: size.width,
                          height: size.height,
                          child: _camera!.buildPreview(),
                        ),
                      ),
                      AnimatedBuilder(
                        animation: _live,
                        builder: (_, _) => CustomPaint(
                          key: const Key('live-scan-outline'),
                          painter: _ScanOutline(
                            _live.corners,
                            _live.geometry,
                            _live.stable,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            )
          else if (_error == null)
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      key: const Key('live-scan-close'),
                      tooltip: 'Cancel scan',
                      color: Colors.white,
                      onPressed: () {
                        _leave();
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.close),
                    ),
                    const Text(
                      'Scan Document',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (_error != null) ...[
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  if (!_capturing)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _error = null;
                        });
                        _enqueue(() async {
                          await _closeCamera();
                          await _start();
                        });
                      },
                      child: const Text('Retry camera'),
                    ),
                ],
                AnimatedBuilder(
                  animation: _live,
                  builder: (_, _) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    color: Colors.black54,
                    child: Text(
                      _capturing
                          ? 'Preparing scan…'
                          : _camera?.guidance != null
                          ? _camera!.guidance!
                          : _live.stable
                          ? 'Document ready • Tap to capture'
                          : _live.corners != null
                          ? 'Hold steady • Tap to capture'
                          : 'Point at a document • You can capture anytime',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: IconButton.filled(
                    key: const Key('live-scan-shutter'),
                    tooltip: 'Capture document',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF2563EB),
                      disabledBackgroundColor: Colors.white38,
                      fixedSize: const Size(76, 76),
                    ),
                    onPressed: _ready && !_capturing ? _capture : null,
                    icon: const Icon(Icons.camera_alt_outlined, size: 34),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ScanOutline extends CustomPainter {
  _ScanOutline(this.corners, this.geometry, this.stable);
  final DocumentCorners? corners;
  final ScanPreviewGeometry? geometry;
  final bool stable;
  @override
  void paint(Canvas canvas, Size size) {
    if (corners == null || geometry == null) return;
    final points = corners!
        .toList()
        .map((p) => geometry!.map(p, size))
        .toList();
    final path = Path()..addPolygon(points, true);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawPath(
      path,
      Paint()
        ..color = (stable ? Colors.greenAccent : Colors.amberAccent).withValues(
          alpha: .12,
        ),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = stable ? Colors.greenAccent : Colors.amberAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScanOutline old) =>
      old.corners != corners ||
      old.geometry != geometry ||
      old.stable != stable;
}
