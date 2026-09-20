import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_client.dart';

/// Manages lightweight, non-blocking background server warm-up (e.g. for Render Free spin-up).
///
/// Ensures only one pre-warm request is in-flight at any time, suppresses all errors
/// from user-visible UI, and respects a cooldown period between pings.
class ServerPrewarmService {
  ServerPrewarmService._();
  static final ServerPrewarmService instance = ServerPrewarmService._();

  Future<bool>? _inFlight;
  DateTime? _lastWarmedAt;
  static const Duration cooldown = Duration(minutes: 5);

  /// Pings `GET /health` in the background with a cold-start-tolerant timeout.
  ///
  /// Returns `true` if server answered, `false` on timeout or failure.
  /// Never throws and never blocks screen transitions.
  Future<bool> prewarm({ApiClient? apiClient}) {
    final now = DateTime.now();
    if (_lastWarmedAt != null && now.difference(_lastWarmedAt!) < cooldown) {
      return Future.value(true);
    }
    if (_inFlight != null) {
      return _inFlight!;
    }

    final client = apiClient ?? ApiClient(timeout: ApiTimeoutPolicy.coldStartTolerant);
    final future = () async {
      try {
        await client.getJson(
          '/health',
          requestTimeout: ApiTimeoutPolicy.coldStartTolerant,
          autoRetry: false,
        );
        _lastWarmedAt = DateTime.now();
        return true;
      } catch (_) {
        // Silent: background pre-warm failure is never exposed to users
        return false;
      } finally {
        _inFlight = null;
        if (apiClient == null) {
          client.close();
        }
      }
    }();

    _inFlight = future;
    return future;
  }

  @visibleForTesting
  void reset() {
    _inFlight = null;
    _lastWarmedAt = null;
  }

  @visibleForTesting
  bool get hasInFlight => _inFlight != null;

  @visibleForTesting
  DateTime? get lastWarmedAt => _lastWarmedAt;
}

