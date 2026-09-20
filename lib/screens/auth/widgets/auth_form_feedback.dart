import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/api_client.dart';
import '../../../services/auth_service.dart';

/// UI-only allowlist: never display raw server exception text or field values.
String authFormError(Object error) {
  if (error is AuthStorageException) return error.message;
  if (error is! ApiException) return 'Something went wrong. Please try again.';
  if (error.statusCode == 429 || error.code == 'RATE_LIMITED') {
    return 'Too many attempts. Please wait a moment and try again.';
  }
  if (error.code == 'SERVER_WAKING') {
    return 'The server is waking up. Please wait a moment and try again.';
  }
  if (error.statusCode != null && error.statusCode! >= 500) {
    return 'Something went wrong on the server. Please try again.';
  }
  switch (error.code) {
    case 'INVALID_CREDENTIALS':
      return 'Incorrect email or password.';
    case 'INVALID_CURRENT_PASSWORD':
      return 'Current password is incorrect.';
    case 'EMAIL_ALREADY_REGISTERED':
      return 'An account with this email already exists.';
    case 'EMAIL_NOT_VERIFIED':
      return 'Your email still needs verification.';
    case 'ACCOUNT_DISABLED':
      return 'This account is disabled. Please contact support.';
    case 'INVALID_OR_EXPIRED_CODE':
      return 'The code is invalid or expired. Check it or request a new code.';
    case 'INVALID_OR_EXPIRED_RESET_TOKEN':
      return 'This password reset has expired. Please request a new code.';
    case 'COLD_START_TIMEOUT':
      return 'The server is taking longer than usual to wake up. Please try again in a few moments.';
    case 'NETWORK_TIMEOUT':
      return 'The server took too long to respond. Please try again.';
    case 'NETWORK_OFFLINE':
      return 'No internet connection. Please check your network and try again.';
    case 'NETWORK_ERROR':
      return 'Unable to connect. Check your internet connection and try again.';
  }
  if (error.statusCode == 401) {
    return 'Your session has expired. Please log in again.';
  }
  if (error.statusCode == 403) {
    return 'You do not have permission to perform this action.';
  }
  if (error.statusCode == 409) {
    return 'This change conflicts with existing data. Please review and try again.';
  }
  if (error.statusCode == 400 || error.code == 'VALIDATION_ERROR') {
    for (final entry in error.fields.entries) {
      switch (entry.key) {
        case 'firstName':
        case 'lastName':
          final messages = entry.value is List
              ? entry.value as List
              : [entry.value];
          if (messages.contains('Names cannot contain numbers.')) {
            return 'Names cannot contain numbers.';
          }
          return '${entry.key == 'firstName' ? 'First' : 'Last'} name must contain 2-100 characters using letters, spaces, hyphens, or apostrophes.';
        case 'email':
          return 'Please enter a valid email address.';
        case 'password':
        case 'newPassword':
          return 'Password must be 8-128 characters and include an uppercase letter, a lowercase letter, and a number.';
        case 'currentPassword':
          return 'Please enter your current password.';
        case 'code':
          return 'Please enter the 6-digit code.';
        case 'program':
          return 'Please select a supported program.';
        case 'yearLevel':
          return 'Please select a year level from 1st Year to 4th Year.';
        case 'school':
          return 'School is set to New Era University.';
      }
    }
    return 'Please check the form fields and try again.';
  }
  return 'The request could not be completed. Please try again.';
}

/// Retain the server's Retry-After delay without weakening server rate limits.
mixin AuthFormFeedback<T extends StatefulWidget> on State<T> {
  Timer? _retryTimer;
  int retrySeconds = 0;
  bool get isRateLimited => retrySeconds > 0;

  String handleFormError(Object error) {
    if (error is ApiException &&
        (error.statusCode == 429 || error.code == 'RATE_LIMITED')) {
      final duration = error.retryAfter ?? const Duration(seconds: 30);
      _retryTimer?.cancel();
      setState(
        () => retrySeconds = (duration.inMilliseconds / 1000).ceil().clamp(
          1,
          86400,
        ),
      );
      _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => retrySeconds--);
        if (retrySeconds <= 0) timer.cancel();
      });
    }
    return authFormError(error);
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }
}

class AuthRetryNotice extends StatelessWidget {
  const AuthRetryNotice({super.key, required this.seconds});
  final int seconds;
  @override
  Widget build(BuildContext context) => seconds <= 0
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            'Try again in $seconds seconds.',
            textAlign: TextAlign.center,
          ),
        );
}
