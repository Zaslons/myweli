/// Market data: how many digits follow each country calling code — a §18 seam
/// (SYSTEM.md §18, multi-pays.md §9), and the ONLY home of that fact in the
/// app. Key = the calling code without `+`.
///
/// Côte d'Ivoire: exactly 10 digits since 31 January 2021 (ARTCI, published by
/// the ITU: https://www.itu.int/oth/T0202000031), the leading 0 included —
/// mobile 01/05/07, fixed 21/25/27. A calling code with no entry gets the
/// generic E.164 rule only: the picker offers every country, and the
/// `intl_phone_field` table is stale for some of them (Bénin is 10 digits since
/// 2024, it says 8), so it is not adopted. Opening a market adds its row here
/// AND in `backend/lib/src/localities/phone_numbering.dart`:
/// `test/unit/phone_numbering_pin_test.dart` holds the two tables equal.
///
/// Design: docs/design/phone-national-length.md
library;

import 'package:intl_phone_field/countries.dart';

const Map<String, int> kNationalNumberLength = {'225': 10};

/// The phone number as one value, everywhere one is typed.
class PhoneNumbering {
  PhoneNumbering._();

  /// Spaces, dashes, dots and brackets — what people type between digits.
  static final RegExp _separators = RegExp(r'[\s\-().]');

  /// [raw] without separators, or `''` when nothing is left but a calling code
  /// from the table (`+225`) — what a cleared field holds is EMPTY, not a
  /// number (phone-national-length.md §2.1).
  static String normalize(String raw) {
    final cleaned = raw.trim().replaceAll(_separators, '');
    if (cleaned.startsWith('+') &&
        kNationalNumberLength.containsKey(cleaned.substring(1))) {
      return '';
    }
    return cleaned;
  }

  /// The value a phone field emits for [national] typed under [callingCode]:
  /// `''` while nothing is typed, else `+<callingCode><national>` without a
  /// separator — what is checked is what is sent. A full number pasted or
  /// autofilled into the national part (« +225 07 07 12 34 56 », « 00225 … »)
  /// carries the field's own code, not more digits: it is dropped once.
  static String compose(String callingCode, String national) {
    var digits = national.trim().replaceAll(_separators, '');
    for (final prefix in ['+$callingCode', '00$callingCode']) {
      if (digits.startsWith(prefix)) {
        digits = digits.substring(prefix.length);
        break;
      }
    }
    return digits.isEmpty ? '' : '+$callingCode$digits';
  }

  /// The longest calling code in the picker's country list that [digits] (an
  /// E.164 number without its `+`) starts with, or `''` — `33612345678` is
  /// France (`33`), not `336`. The one reading of a stored number's calling
  /// code: `PhoneNumberField`'s prefill, `Helpers.maskPhoneNumber` and the
  /// client list's `maskClientPhone` (which took the first three digits,
  /// whatever the country — phone-leftovers.md §8) all ask here.
  static String callingCodeOf(String digits) {
    var longest = '';
    for (final country in countries) {
      final code = country.fullCountryCode;
      if (digits.startsWith(code) && code.length > longest.length) {
        longest = code;
      }
    }
    return longest;
  }

  /// The national-length rule for [e164] (`+` then digits, no separator), or
  /// null when its calling code has no entry. Calling codes are prefix-free
  /// (ITU-T E.164), so the first match is the only one — the backend's
  /// `nationalLengthRule`, in Dart for the app.
  static ({String callingCode, int length})? nationalLengthFor(String e164) {
    if (!e164.startsWith('+')) return null;
    for (final entry in kNationalNumberLength.entries) {
      if (e164.startsWith('+${entry.key}')) {
        return (callingCode: entry.key, length: entry.value);
      }
    }
    return null;
  }
}
