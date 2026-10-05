import 'dart:async';

/// Coordinates OCR extraction across the entire application instance,
/// ensuring at most [maxConcurrent] (default 1) persisted OCR operations
/// run at any given moment.
class AppOcrCoordinator {
  AppOcrCoordinator({this.maxConcurrent = 1});

  final int maxConcurrent;
  int _activeCount = 0;
  int _maxObservedConcurrent = 0;
  final List<Completer<void>> _waiters = [];

  int get activeCount => _activeCount;
  int get waitingCount => _waiters.length;
  int get maxObservedConcurrent => _maxObservedConcurrent;

  Future<T> runGuarded<T>(Future<T> Function() action) async {
    while (_activeCount >= maxConcurrent) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }

    _activeCount++;
    if (_activeCount > _maxObservedConcurrent) {
      _maxObservedConcurrent = _activeCount;
    }

    try {
      return await action();
    } finally {
      _activeCount--;
      if (_waiters.isNotEmpty) {
        final next = _waiters.removeAt(0);
        if (!next.isCompleted) {
          next.complete();
        }
      }
    }
  }

  void resetStats() {
    _maxObservedConcurrent = _activeCount;
  }
}

