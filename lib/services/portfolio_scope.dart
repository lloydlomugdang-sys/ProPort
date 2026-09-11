import 'package:flutter/widgets.dart';

import 'portfolio_service.dart';

class PortfolioScope extends InheritedNotifier<PortfolioService> {
  const PortfolioScope({
    super.key,
    required PortfolioService portfolioService,
    required super.child,
  }) : super(notifier: portfolioService);

  static PortfolioService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PortfolioScope>();
    assert(scope != null, 'No PortfolioScope found above this context.');
    return scope!.notifier!;
  }
}
