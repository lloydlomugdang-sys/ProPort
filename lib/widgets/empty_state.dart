// LOCATION: lib/widgets/empty_state.dart

import 'package:flutter/material.dart';
import 'app_empty_state.dart';

/// Legacy [EmptyState] preserved for backwards compatibility.
/// Delegates to [AppEmptyState] with the modern GradPort empty-state design.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IconData icon;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      title: message,
      description: subtitle ?? '',
      icon: icon,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}