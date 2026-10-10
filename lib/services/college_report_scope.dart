import 'package:flutter/widgets.dart';
import 'college_report_service.dart';

class CollegeReportScope extends InheritedNotifier<CollegeReportService> {
  const CollegeReportScope({
    super.key,
    required CollegeReportService service,
    required super.child,
  }) : super(notifier: service);
  static CollegeReportService? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<CollegeReportScope>()
      ?.notifier;
  static CollegeReportService of(BuildContext context) => maybeOf(context)!;
}
