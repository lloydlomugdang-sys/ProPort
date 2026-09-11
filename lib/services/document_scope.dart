import 'package:flutter/widgets.dart';

import 'document_service.dart';

class DocumentScope extends InheritedNotifier<DocumentService> {
  const DocumentScope({
    super.key,
    required DocumentService documentService,
    required super.child,
  }) : super(notifier: documentService);

  static DocumentService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DocumentScope>();
    assert(scope != null, 'No DocumentScope found above this context.');
    return scope!.notifier!;
  }
}
