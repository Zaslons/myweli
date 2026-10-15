/// Boundary input validators shared by route handlers (docs/BACKEND.md §3.4).
/// The server validates every input; the client is never trusted.
library;

import 'localities/phone_numbering.dart';

/// A valid phone number, in canonical E.164 form: `+` then 8–15 digits, first
/// non-zero — AND, when the calling code has a row in the numbering table
/// (`localities/phone_numbering.dart`, the market-data seam), exactly that
/// many digits after it: `+225` → 10. Any other calling code gets the generic
/// rule only.
///
/// No separator stripping: the server accepts only the canonical form, the
/// clients normalise before sending. `''`, or a calling code alone, is not a
/// number — an optional field that may be cleared checks for empty first.
/// Design: docs/design/phone-national-length.md §2.4.
bool isValidPhoneNumber(String value) {
  final v = value.trim();
  if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(v)) return false;
  final rule = nationalLengthRule(v);
  if (rule == null) return true;
  return v.length - 1 - rule.callingCode.length == rule.length;
}

/// A numeric OTP code of 4–8 digits.
bool isValidOtpCode(String value) =>
    RegExp(r'^\d{4,8}$').hasMatch(value.trim());

/// A plausible email address (pragmatic: local@domain.tld, ≤ 254 chars).
bool isValidEmail(String value) {
  final v = value.trim();
  return v.length <= 254 && RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);
}
