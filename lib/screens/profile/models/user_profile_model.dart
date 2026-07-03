// LOCATION: lib/screens/profile/models/user_profile_model.dart
//
// Temporary in-memory state only.
// Replace UserProfileNotifier with a real MongoDB / API service later.

import 'package:flutter/foundation.dart';

/// Immutable user profile data class.
/// Structure mirrors what will eventually come from MongoDB.
class UserProfile {
  const UserProfile({
    required this.fullName,
    required this.email,
    required this.program,
    required this.yearLevel,
    required this.school,
    this.avatarPath, // null = use default icon
  });

  final String fullName;
  final String email;
  final String program;
  final String yearLevel;
  final String school;
  final String? avatarPath;

  /// Creates a copy with updated fields.
  UserProfile copyWith({
    String? fullName,
    String? email,
    String? program,
    String? yearLevel,
    String? school,
    String? avatarPath,
    bool clearAvatar = false,
  }) =>
      UserProfile(
        fullName:   fullName   ?? this.fullName,
        email:      email      ?? this.email,
        program:    program    ?? this.program,
        yearLevel:  yearLevel  ?? this.yearLevel,
        school:     school     ?? this.school,
        avatarPath: clearAvatar ? null : (avatarPath ?? this.avatarPath),
      );

  /// Convert to a map for future MongoDB / API submission.
  Map<String, dynamic> toMap() => {
        'fullName':   fullName,
        'email':      email,
        'program':    program,
        'yearLevel':  yearLevel,
        'school':     school,
        'avatarPath': avatarPath,
      };

  /// MOCK DATA — replace with a real fetch from MongoDB when backend is ready.
  static UserProfile get mock => const UserProfile(
        fullName:  'John Dela Cruz',
        email:     'john.delacruz@gmail.com',
        program:   'Bachelor of Science in Information Technology',
        yearLevel: '3rd Year',
        school:    'New Era University',
      );
}

/// In-memory profile state.
/// Wraps [UserProfile] in a [ChangeNotifier] so any screen can listen and
/// rebuild when the profile is updated. Replace the internal state with a
/// real MongoDB call in [updateProfile] when the backend is ready.
class UserProfileNotifier extends ChangeNotifier {
  UserProfile _profile = UserProfile.mock;

  UserProfile get profile => _profile;

  /// Update profile fields and notify listeners.
  /// TODO: Replace with MongoDB / API call.
  void updateProfile(UserProfile updated) {
    _profile = updated;
    notifyListeners();
  }
}

/// Global singleton notifier — accessed directly in screens.
/// For a larger app, inject this via Provider / Riverpod / GetIt.
/// Keeping it simple here so it's easy to swap out later.
final userProfileNotifier = UserProfileNotifier();