# GradPort live classical scanner

This scanner uses camera buffers only for local, classical boundary detection.
No live frame goes to OCR, Gemini or the backend. The accepted Review Scan JPEG
continues through the existing Tesseract and Gemini **text-only** workflow.

## Implementation and limits

- Official `camera 0.12.0+2`, compatible with this project's Flutter 3.41.9 /
  Dart 3.11.5. No existing dependency version upgrades. The later 0.12.1 release
  requires Dart 3.12; upgrading the SDK is outside this task.
- Rear camera only; still capture, no audio or automatic shutter. Native camera
  preview uses a centered `BoxFit.cover` in a clipped viewport.
- The `veryHigh` preset requests a 1080p-class still/preview; the device decides
  the supported resolution. Detection samples at most 640 pixels on the long
  edge. Correction uses the full captured image, never the sampled frame.
- At most one isolate job is in flight. Frames are rejected before copying if
  busy or less than `max(350 ms, last processing duration + 80 ms)` from the last
  accepted frame. There is no queued backlog. These are limits, not a promised
  physical-device frame rate.
- Three similar confident detections mark the outline ready. Smoothing uses
  65% new / 35% previous coordinates. An isolated large jump is withheld; a
  repeated new position is allowed. Ambiguity clears the outline, misses remove
  the ready state, and the outline expires 1 second after the last valid frame.
- Android YUV/NV21 sensor coordinates use sensor minus device rotation; iOS BGRA
  buffers are already oriented by AVFoundation. The preview and overlay use the
  same centered fit. Mirroring has explicit mapping tests, but front-camera
  capture is deliberately not enabled.
- If a device negotiates incompatible stream/preview aspect ratios (or an
  unsupported pixel layout), a safe message replaces the live outline. The
  public camera API does not expose a native crop rectangle, so GradPort does
  not guess one. Still capture/refinement/review remain available.
- At shutter, live tracking stops and the existing detector runs once on the
  EXIF-normalized still, bounded to 800 pixels. Its normalized corners map to
  full-source pixels for the existing perspective correction/enhancement.
  Low confidence preserves the full photo, with manual corners/full-photo undo.
- Backgrounding, cancellation and disposal invalidate detection results and
  serialize camera shutdown. Retake creates a fresh camera session. An already
  running bounded isolate job can finish, but its stale result is discarded.
- Android microphone/legacy read/write storage permissions contributed by the camera
  plugin are removed: this is a cache-based still-image flow. iOS requires only
  the camera purpose string, with audio disabled.

## Physical acceptance checklist (pending)

Automated geometry, lifecycle and fixture tests do **not** validate real camera
alignment, autofocus, thermal behavior or phone performance. On a real Android
phone, record device/Android version and check:

- [ ] White paper on a dark table; then white paper on a light table.
- [ ] Certificate with colored border; transcript/text-heavy paper.
- [ ] Portrait, both landscape orientations, rotation during preview.
- [ ] Skewed/angled paper; document close to frame boundaries.
- [ ] Shadows, mild glare, clutter, two competing sheets (must not show ready).
- [ ] Slight hand movement: outline tracks edges without large isolated jumps.
- [ ] Remove/reintroduce paper: ready clears and stale outline expires.
- [ ] Capture at stable and unstable states; final crop matches the STILL.
- [ ] Blank/low-contrast view: full-photo fallback, not an arbitrary inset.
- [ ] Adjust corners, Preview Scan, Use full photo, enhancement, Retake, Cancel.
- [ ] Permission denial/retry/settings; background/resume; rapid shutter taps;
  exit during initialization/capture; repeated scans without camera leaks.
- [ ] Accept scan -> readable Tesseract text -> text-only classification ->
  upload; manual category overrides remain authoritative.
- [ ] Gallery import, multi-page/compiled PDF and portfolio flows still work.
- [ ] Inspect sharpness at zoom, motion blur, crop alignment and UI responsiveness;
  repeat on a lower-end phone. No phone FPS or physical acceptance is claimed.

Run the equivalent lifecycle/orientation/permission checks on iOS before iOS
release (camera plugin/platform builds cannot be physically verified on Windows).

## Android release test build

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://gradport-ocr-test.onrender.com
```

Use `build/app/outputs/flutter-apk/app-release.apk`. This API define is required;
a release APK without it is not representative of the GradPort test environment.
No backend deployment or database maintenance is part of this scanner change.
