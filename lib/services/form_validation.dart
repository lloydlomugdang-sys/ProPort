String? personalNameError(String value, [String label = 'name']) {
  final name = value.trim();
  if (RegExp(r'\p{N}', unicode: true).hasMatch(name)) {
    return 'Names cannot contain numbers.';
  }
  if (name.isEmpty) return 'Please enter your $label.';
  if (name.length < 2 || name.length > 100) {
    return '$label must contain 2-100 characters.';
  }
  if (!RegExp(r"^[\p{L}\p{M} '\u2019-]+$", unicode: true).hasMatch(name) ||
      !RegExp(r'\p{L}', unicode: true).hasMatch(name)) {
    return 'Use letters, spaces, hyphens, or apostrophes for names.';
  }
  return null;
}

String? newPasswordError(String password) {
  if (password.isEmpty) return 'Please enter your new password.';
  if (password.length < 8 ||
      password.length > 128 ||
      !RegExp(r'[A-Z]').hasMatch(password) ||
      !RegExp(r'[a-z]').hasMatch(password) ||
      !RegExp(r'[0-9]').hasMatch(password)) {
    return 'Password must be 8-128 characters and include an uppercase letter, a lowercase letter, and a number.';
  }
  return null;
}
