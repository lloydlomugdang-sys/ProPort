import 'dart:convert';
import 'dart:io';
import 'package:proport_app/services/portfolio_template.dart';

// Test fixture reads the actual backend configuration, not a second order array.
Map<String, dynamic> portfolioTemplateJson() => Map<String, dynamic>.from(
  (jsonDecode(
                File(
                  'backend/src/config/portfolio-templates.json',
                ).readAsStringSync(),
              )['templates']
              as List)
          .singleWhere((t) => t['status'] == 'active')
      as Map,
);
PortfolioTemplate testPortfolioTemplate() =>
    PortfolioTemplate.fromJson(portfolioTemplateJson());
Map<String, dynamic> portfolioTemplateEnvelope() => {
  'data': {'template': portfolioTemplateJson()},
};
