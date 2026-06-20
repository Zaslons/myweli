class ApiConstants {
  // Base URL (will be used when backend is ready)
  static const String baseUrl = 'https://api.myweli.com';
  
  // API Endpoints
  static const String login = '/auth/login';
  static const String verifyOtp = '/auth/verify-otp';
  static const String providers = '/providers';
  static const String providerDetail = '/providers/{id}';
  static const String services = '/providers/{id}/services';
  static const String appointments = '/appointments';
  static const String appointmentDetail = '/appointments/{id}';
  static const String availability = '/providers/{id}/availability';
  static const String bookAppointment = '/appointments/book';
  static const String cancelAppointment = '/appointments/{id}/cancel';
  
  // Headers
  static const String contentType = 'application/json';
  static const String authorization = 'Authorization';
  static const String bearer = 'Bearer';
}



