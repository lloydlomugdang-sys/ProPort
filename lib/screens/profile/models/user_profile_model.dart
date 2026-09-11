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
  });

  factory UserProfile.fromAuthUser(AuthUser user) {
    return UserProfile(
      firstName: user.firstName,
      lastName: user.lastName,
      email: user.email,
      program: user.program,
      yearLevel: user.yearLevel,
      school: user.school,
    );
  }

  final String firstName;
  final String lastName;
  final String email;
  final String program;
  final String yearLevel;
  final String school;

  String get fullName => '$firstName $lastName'.trim();
}
