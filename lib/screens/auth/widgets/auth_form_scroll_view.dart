import 'package:flutter/material.dart';

/// A single, full-viewport scroll surface for keyboard-resized auth forms.
///
/// The enclosing Scaffold handles viewInsets and SafeArea handles system padding.
/// Using those actual constraints avoids centering inside the full screen height
/// when the keyboard is open (or subtracting the keyboard inset twice).
class AuthFormScrollView extends StatelessWidget {
  const AuthFormScrollView({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - padding.vertical).clamp(
              0.0,
              double.infinity,
            ),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}
