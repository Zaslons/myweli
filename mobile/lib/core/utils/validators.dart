class Validators {
  /// Validates an international phone number in E.164 (`+` then 8–15 digits) —
  /// mirrors the backend. The country-code picker ([PhoneNumberField]) also
  /// enforces per-country length; this is the generic fallback check.
  static String? phoneNumber(String? value) {
    if (value == null || value.isEmpty) {
      return 'Le numéro de téléphone est requis';
    }
    final cleaned = value.replaceAll(RegExp(r'[\s\-()]'), '');
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(cleaned)) {
      return 'Numéro de téléphone invalide';
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
