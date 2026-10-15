/// Market data: how many digits follow each country calling code. This is
/// the ONLY home of that fact on the server (multi-pays.md §9 — the
/// `localities/` seam). Key = the calling code without `+`.
///
/// Côte d'Ivoire: exactly 10 digits since 31 January 2021 (ARTCI, published
/// by the ITU: https://www.itu.int/oth/T0202000031), the leading 0 included.
/// A calling code with no entry gets the generic E.164 rule only. Opening a
/// market adds its row here: `test/localities/phone_numbering_test.dart`
/// fails while a seeded country has none, and the app's and the web's own
/// tables are pinned to this one.
///
/// Design: docs/design/phone-national-length.md
library;

const Map<String, int> nationalNumberLengths = {'225': 10};

/// The national-length rule for [e164] (`+` then digits, no separator), or
/// null when its calling code has no entry. Calling codes are prefix-free
/// (ITU-T E.164), so the first match is the only one.
({String callingCode, int length})? nationalLengthRule(String e164) {
  if (!e164.startsWith('+')) return null;
  for (final entry in nationalNumberLengths.entries) {
    if (e164.startsWith('+${entry.key}')) {
      return (callingCode: entry.key, length: entry.value);
    }
  }
  return null;
}
