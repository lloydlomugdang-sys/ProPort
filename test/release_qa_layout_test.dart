import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:proport_app/screens/files/widgets/scholastic_fields.dart';
import 'package:proport_app/services/scholastic_details.dart';
import 'package:proport_app/screens/settings/about_screen.dart';
import 'package:proport_app/screens/settings/help_center_screen.dart';

void main() {
  testWidgets(
    'shared TOR controls fit narrow review forms and preserve explicit choices',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var details = const ScholasticDetails();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: StatefulBuilder(
                builder: (_, setState) => ScholasticFields(
                  value: details,
                  onChanged: (value) => setState(() => details = value),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField), '2');
      await tester.pump();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2nd Semester').last);
      await tester.pumpAndSettle();
      expect(details.reflectionSatisfied(''), isFalse);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(details.toJson(), {
        'studyYear': 2,
        'semester': '2nd Semester',
        'reflectionIncluded': true,
      });
      expect(details.reflectionSatisfied(''), isTrue);
    },
  );
  for (final screen in [const AboutScreen(), const HelpCenterScreen()]) {
    testWidgets(
      '${screen.runtimeType} fits a narrow screen with accurate wording',
      (tester) async {
        GoogleFonts.config.allowRuntimeFetching = false;
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(home: screen));
        await tester.pumpAndSettle();
        final text = tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data ?? '')
            .join(' ');
        expect(text.toLowerCase(), isNot(contains('ml kit')));
        expect(text.toLowerCase(), isNot(contains('tracker')));
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -1800),
        );
        await tester.pumpAndSettle();
      },
    );
  }
}
