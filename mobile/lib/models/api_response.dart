class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? message;
  final String? error;

  /// Optional machine-readable error code (e.g. `otp_expired`) so callers can
  /// branch on the failure kind instead of parsing the human message.
  final String? code;

  const ApiResponse({
    required this.success,
    this.data,
    this.message,
    this.error,
    this.code,
  });

  factory ApiResponse.success(T data, {String? message}) {
    return ApiResponse(
      success: true,
      data: data,
      message: message,
    );
  }

  factory ApiResponse.error(String error, {String? message, String? code}) {
    return ApiResponse(
      success: false,
      error: error,
      message: message,
      code: code,
    );
  }
}
