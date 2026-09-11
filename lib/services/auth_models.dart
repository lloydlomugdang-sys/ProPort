enum VerificationPurpose { emailVerification, passwordReset }

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.program,
    required this.yearLevel,
    required this.school,
    required this.status,
    required this.emailVerifiedAt,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String,
      email: json['email'] as String,
      firstName: json['firstName'] as String,
      lastName: json['lastName'] as String,
      program: json['program'] as String? ?? '',
      yearLevel: json['yearLevel'] as String? ?? '',
      school: json['school'] as String? ?? '',
      status: json['status'] as String,
      emailVerifiedAt: _optionalDateTime(json['emailVerifiedAt']),
    );
  }

  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final String program;
  final String yearLevel;
  final String school;
  final String status;
  final DateTime? emailVerifiedAt;

  static DateTime? _optionalDateTime(Object? value) {
    if (value == null) return null;
    return DateTime.parse(value as String);
  }
}

class AuthSession {
  const AuthSession({
    required this.user,
    required this.tokenType,
    required this.accessToken,
    required this.accessTokenExpiresAt,
    required this.refreshToken,
    required this.refreshTokenExpiresAt,
  });

  factory AuthSession.fromData(Map<String, dynamic> data) {
    final user = data['user'];
    final tokens = data['tokens'];
    if (user is! Map<String, dynamic> || tokens is! Map<String, dynamic>) {
      throw const FormatException('Invalid authentication response.');
    }

    return AuthSession(
      user: AuthUser.fromJson(user),
      tokenType: tokens['tokenType'] as String,
      accessToken: tokens['accessToken'] as String,
      accessTokenExpiresAt: DateTime.parse(
        tokens['accessTokenExpiresAt'] as String,
      ),
      refreshToken: tokens['refreshToken'] as String,
      refreshTokenExpiresAt: DateTime.parse(
        tokens['refreshTokenExpiresAt'] as String,
      ),
    );
  }

  final AuthUser user;
  final String tokenType;
  final String accessToken;
  final DateTime accessTokenExpiresAt;
  final String refreshToken;
  final DateTime refreshTokenExpiresAt;
}
