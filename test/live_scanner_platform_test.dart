import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('still scanner strips video audio and legacy write permissions', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    for (final permission in [
      'RECORD_AUDIO',
      'WRITE_EXTERNAL_STORAGE',
      'READ_EXTERNAL_STORAGE',
    ]) {
      final declaration = RegExp(
        '<uses-permission[^>]*android:name="android.permission.$permission"[^>]*>',
      ).firstMatch(manifest)?.group(0);
      expect(declaration, isNotNull);
      expect(declaration, contains('tools:node="remove"'));
    }
    expect(
      manifest,
      contains(
        'android:name="android.hardware.camera.any" android:required="false"',
      ),
    );
    expect(manifest, contains('android:required="false" tools:node="replace"'));
  });
  test('iOS has a camera purpose string; scanner does not request audio', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('<key>NSCameraUsageDescription</key>'));
    expect(
      File('lib/services/scanner/scanner_camera.dart').readAsStringSync(),
      contains('enableAudio: false'),
    );
  });
}
