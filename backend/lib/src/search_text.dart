/// Free-text search over salons (`GET /providers?q=`): the cleaning and the
/// fold both twins share. docs/design/consumer-search.md §3 (A4-api,
/// decision 228).
///
/// **The search text is cleaned in Dart, once, for both twins**, so they
/// cannot disagree on what was asked. **The salon's text is prepared where
/// the data is:** Postgres runs `lower(unaccent(regexp_replace(…)))`, the
/// in-memory twin [searchableText], whose fold table is copied from that very
/// `unaccent` (`search_fold_table.dart`). The Postgres suite holds the table
/// to `unaccent()` entry for entry over every code point, and
/// [searchableText] to the SQL over Latin, its accents, white space,
/// punctuation and the full-width forms (not over every script: §3.1 of the
/// spec gives the measured limit).
library;

import 'search_fold_table.dart';

/// Only the first 100 characters of a search are used (§3).
const kSearchTextMaxCharacters = 100;

/// A run of white space: Dart's `\s`, written out so that Postgres's
/// `regexp_replace` reads the very same class (its own `\s` follows the
/// database's locale, which leaves out the no-break spaces). The no-break
/// space a French keyboard types before « : » and the narrow one before
/// « ; » included. Collapsed to one space in the search AND in the salon's
/// text, so « Beauté␣␣Divine » is found by « beaute divine ».
const kSearchSpaces =
    r'[\t\n\v\f\r \u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+';

final _whiteSpace = RegExp(kSearchSpaces);

/// What a search for [raw] looks for, or null when it looks for nothing.
///
/// Spaces are trimmed and every run of them becomes one; then the first
/// [kSearchTextMaxCharacters] characters are kept, counted as code points
/// (runes), so a character outside the Basic Multilingual Plane (most emoji)
/// is never split into half a surrogate pair. A sequence of several (a flag,
/// a family) can still be cut between them. An empty or blank text is no
/// filter; so, in effect, is one with nothing left once folded (a lone
/// combining accent): its pattern is `%%`, on both twins.
String? cleanSearchText(String? raw) {
  if (raw == null) return null;
  final collapsed = raw.replaceAll(_whiteSpace, ' ').trim();
  if (collapsed.isEmpty) return null;
  final runes = collapsed.runes;
  if (runes.length <= kSearchTextMaxCharacters) return collapsed;
  return String.fromCharCodes(runes.take(kSearchTextMaxCharacters)).trimRight();
}

/// [text] folded as Postgres's `lower(unaccent(text))` folds it: each
/// character through [kUnaccentFold] first, then lower case. That order is
/// the database's, and it matters: unaccent turns « Ɩ » into « I », where
/// lower-casing first gives « ɩ », which the table leaves alone.
String foldSearchText(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    final folded = kUnaccentFold[rune];
    if (folded == null) {
      out.writeCharCode(rune);
    } else {
      out.write(folded);
    }
  }
  return out.toString().toLowerCase();
}

/// A salon's [field] as a search compares it: white space collapsed as in
/// the search ([kSearchSpaces]), then folded. Postgres's
/// `lower(unaccent(regexp_replace(field, kSearchSpaces, ' ', 'g')))`.
String searchableText(String field) =>
    foldSearchText(field.replaceAll(_whiteSpace, ' '));

/// The salon document fields a search reads, each on its own.
const _searchedFields = ['name', 'description', 'address', 'commune'];

/// Whether [salon] holds [needle] (already cleaned and folded) in one of the
/// fields a search reads: its name, description, address or commune, or the
/// name of one of its active services.
///
/// **Each field on its own:** a text spanning the end of the name and the
/// start of the description matches neither, as on Postgres. A field that
/// is missing or not text matches nothing (never the text « null »). A
/// service with no `active` flag is active, as Postgres's column defaults.
bool salonMatchesSearch(Map<String, dynamic> salon, String needle) {
  bool holds(Object? value) =>
      value is String && searchableText(value).contains(needle);
  for (final field in _searchedFields) {
    if (holds(salon[field])) return true;
  }
  final services = salon['services'];
  if (services is List) {
    for (final service in services) {
      if (service is! Map || service['active'] == false) continue;
      if (holds(service['name'])) return true;
    }
  }
  return false;
}
