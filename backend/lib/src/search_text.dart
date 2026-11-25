/// Free-text search over salons (`GET /providers?q=`): the cleaning and the
/// fold both twins share. docs/design/consumer-search.md §3 (A4-api,
/// decision 228).
///
/// **The cleaning runs in Dart, once, for both twins**, so they cannot
/// disagree on what was asked. **The fold runs where the data is:** Postgres
/// folds with `lower(unaccent(…))`, and the in-memory twin with
/// [foldSearchText], whose table is copied from that very function
/// (`search_fold_table.dart`). The Postgres suite compares the two on every
/// character of the Basic Multilingual Plane.
library;

import 'search_fold_table.dart';

/// Only the first 100 characters of a search are used (§3).
const kSearchTextMaxCharacters = 100;

/// Any run of white space, the no-break space a French keyboard types
/// before « : » included.
final _whiteSpace = RegExp(r'\s+');

/// What a search for [raw] looks for, or null when it looks for nothing.
///
/// Spaces are trimmed and every run of them becomes one; then the first
/// [kSearchTextMaxCharacters] characters are kept, counted as characters
/// (runes), so an emoji at the cut is kept whole rather than split into half
/// a surrogate pair. An empty or blank text is no filter.
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
/// the database's, and it matters: unaccent turns « İ » into « I », where
/// lower-casing first would leave a combining dot behind.
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
      value is String && foldSearchText(value).contains(needle);
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
