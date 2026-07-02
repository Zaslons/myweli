/// Boundary input validators shared by route handlers (docs/BACKEND.md §3.4).
/// The server validates every input; the client is never trusted.
library;

/// A plausible E.164 phone number: `+` then 8–15 digits, first non-zero.
bool isValidE164(String value) =>
    RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value.trim());

/// A numeric OTP code of 4–8 digits.
bool isValidOtpCode(String value) =>
    RegExp(r'^\d{4,8}$').hasMatch(value.trim());

/// A plausible email address (pragmatic: local@domain.tld, ≤ 254 chars).
bool isValidEmail(String value) {
  final v = value.trim();
  return v.length <= 254 && RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);
}
