class Validators {
  /// Validates phone number (Côte d'Ivoire format: +225 XX XX XX XX)
  static String? phoneNumber(String? value) {
    if (value == null || value.isEmpty) {
      return 'Le numéro de téléphone est requis';
    }

    // Remove spaces and special characters
    final cleaned = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    // Check if starts with +225
    if (!cleaned.startsWith('+225')) {
      return 'Le numéro doit commencer par +225';
    }

    // Check length (+225 + 8 digits = 12 total)
    if (cleaned.length != 12) {
      return 'Le numéro doit contenir 8 chiffres après +225';
    }

    // Check if remaining characters are digits
    final digits = cleaned.substring(4);
    if (!RegExp(r'^\d{8}$').hasMatch(digits)) {
      return 'Le numéro doit contenir uniquement des chiffres';
    }

    return null;
  }

  /// Validates OTP code (6 digits)
  static String? otp(String? value) {
    if (value == null || value.isEmpty) {
      return 'Le code est requis';
    }

    if (value.length != 6) {
      return 'Le code doit contenir 6 chiffres';
    }

    if (!RegExp(r'^\d{6}$').hasMatch(value)) {
      return 'Le code doit contenir uniquement des chiffres';
    }

    return null;
  }

  /// Validates name
  static String? name(String? value) {
    if (value == null || value.isEmpty) {
      return 'Le nom est requis';
    }

    if (value.length < 2) {
      return 'Le nom doit contenir au moins 2 caractères';
    }

    return null;
  }

  /// Validates email (optional)
  static String? email(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Email is optional
    }

    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );

    if (!emailRegex.hasMatch(value)) {
      return 'Adresse email invalide';
    }

    return null;
  }

  /// Validates required field
  static String? required(String? value, {String? fieldName}) {
    if (value == null || value.isEmpty) {
      return '${fieldName ?? 'Ce champ'} est requis';
    }
    return null;
  }
}
