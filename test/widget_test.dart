// LOCATION: test/widget_test.dart
// REPLACE the existing file entirely.
// FIX: old test referenced 'MyApp' which no longer exists — replaced with GradPortApp.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/main.dart';

void main() {
  testWidgets('GradPort app launches successfully',
      (WidgetTester tester) async {
    await tester.pumpWidget(const GradPortApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}