import '../../../services/auth_models.dart';

/// Safe current-user fields displayed by the Profile UI.
class UserProfile {
  const UserProfile({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.program,
    required this.yearLevel,
    required this.school,
    this.hasAvatar = false,
  });

  factory UserProfile.fromAuthUser(AuthUser user) {
    return UserProfile(
      firstName: user.firstName,
      lastName: user.lastName,
      email: user.email,
      program: user.program,
      yearLevel: user.yearLevel,
      school: user.school,
      hasAvatar: user.hasAvatar,
    );
  }

  final String firstName;
  final String lastName;
  final String email;
  final String program;
  final String yearLevel;
  final String school;
  final bool hasAvatar;

  String get fullName => '$firstName $lastName'.trim();

  String get initials {
    final first = firstName.trim().isNotEmpty ? firstName.trim()[0] : '';
    final last = lastName.trim().isNotEmpty ? lastName.trim()[0] : '';
    final result = '$first$last'.toUpperCase();
    return result.isNotEmpty
        ? result
        : (email.isNotEmpty ? email[0].toUpperCase() : 'U');
  }
}
