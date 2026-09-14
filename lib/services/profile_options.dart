import 'api_client.dart';

/// Server-owned choices; no separate client program catalogue.
class ProfileOptions {
  const ProfileOptions({
    required this.programs,
    required this.yearLevels,
    required this.school,
  });
  final List<String> programs;
  final List<String> yearLevels;
  final String school;

  factory ProfileOptions.fromJson(Object? value) {
    if (value is Map<String, dynamic> &&
        value['programs'] is List &&
        value['yearLevels'] is List &&
        value['school'] is String) {
      final programs = value['programs'] as List;
      final years = value['yearLevels'] as List;
      if (programs.every((v) => v is String) &&
          years.every((v) => v is String)) {
        return ProfileOptions(
          programs: List<String>.unmodifiable(programs),
          yearLevels: List<String>.unmodifiable(years),
          school: value['school'] as String,
        );
      }
    }
    throw const ApiException(
      code: 'INVALID_RESPONSE',
      message: 'Profile choices are unavailable. Please try again.',
    );
  }
}
