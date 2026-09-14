import 'package:flutter/widgets.dart';

import 'portfolio_service.dart';
import 'portfolio_export_service.dart';

class PortfolioScope extends InheritedNotifier<PortfolioService> {
  const PortfolioScope({
    super.key,
    required PortfolioService portfolioService,
    this.exporter = const DevicePortfolioExporter(),
    required super.child,
  }) : super(notifier: portfolioService);

  final PortfolioExporter exporter;

  @override
  bool updateShouldNotify(covariant PortfolioScope oldWidget) =>
      exporter != oldWidget.exporter || super.updateShouldNotify(oldWidget);

  static PortfolioExporter exporterOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<PortfolioScope>()
            ?.exporter ??
        const DevicePortfolioExporter();
  }

  static PortfolioService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PortfolioScope>();
    assert(scope != null, 'No PortfolioScope found above this context.');
    return scope!.notifier!;
  }
}
