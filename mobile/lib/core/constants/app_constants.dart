class AppConstants {
  // App Info
  static const String appName = 'Myweli';
  static const String appVersion = '1.0.0';

  // Country Code (Côte d'Ivoire)
  static const String defaultCountryCode = '+225';
  static const String defaultCountry = 'CI';

  // OTP
  static const int otpLength = 6;
  static const int otpResendCooldownSeconds = 60;

  // Pagination
  static const int itemsPerPage = 20;

  // Timeouts
  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration mockDelay = Duration(milliseconds: 300);

  // Image Placeholders
  static const String placeholderProviderImage =
      'https://via.placeholder.com/400x300?text=Provider';
  static const String placeholderAvatar =
      'https://via.placeholder.com/100?text=User';
}



