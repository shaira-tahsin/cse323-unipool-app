class AuthValidator {
  static const String _allowedDomain = 'northsouth.edu';

  static bool isValidUniversityEmail(String email) {
    return email.trim().toLowerCase().endsWith('@$_allowedDomain');
  }

  static String? validateEmail(String? email) {
    if (email == null || email.trim().isEmpty) {
      return 'Email is required';
    }
    if (!isValidUniversityEmail(email)) {
      return 'Must use your @northsouth.edu email';
    }
    return null;
  }

  static String? validateName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return 'Name is required';
    }
    return null;
  }

  static String? validatePhone(String? phone) {
    if (phone == null || phone.trim().isEmpty) {
      return 'Phone number is required';
    }
    return null;
  }
}
