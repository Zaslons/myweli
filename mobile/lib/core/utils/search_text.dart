/// What the salon search sends (docs/design/consumer-search.md §2.3).
///
/// **The app never matches a salon itself:** what the text finds is the
/// server's (§3, decision 228). The app only cleans the text before it goes,
/// the way the server cleans it (`backend/lib/src/search_text.dart`), so the
/// two agree on what was asked — and removes what the server refuses: a C0
/// control character in a query answers 400 (`query_sanity.dart`), and a tab
/// pasted into the field would have turned a search into an error.
library;

/// Only the first 100 characters of a search are used (§3). The field takes
/// no more either (`maxLength`).
const kSearchTextMaxCharacters = 100;

/// Below this many characters the list asks nothing (§2.3): one letter
/// matches almost every salon, and it is a request per key on a slow phone.
const kSearchMinCharacters = 2;

/// A run of white space — the server's `kSearchSpaces`, character for
/// character: Dart's `\s`, the no-break spaces included.
final _whiteSpace = RegExp(
  r'[\t\n\v\f\r \u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+',
);

/// What is left of the C0 controls once the white space is a space, and DEL.
final _control = RegExp(r'[\u0000-\u001F\u007F]');

/// [raw] as the search sends it: every run of white space one space (a tab
/// or a line break included), the other control characters removed, trimmed,
/// and cut at [kSearchTextMaxCharacters] characters counted as code points —
/// an emoji at the cut stays whole. Empty when nothing is left.
String cleanSearchText(String raw) {
  final spaced = raw.replaceAll(_whiteSpace, ' ');
  final clean = spaced.replaceAll(_control, '').replaceAll(_whiteSpace, ' ');
  final trimmed = clean.trim();
  final runes = trimmed.runes;
  if (runes.length <= kSearchTextMaxCharacters) return trimmed;
  return String.fromCharCodes(runes.take(kSearchTextMaxCharacters)).trimRight();
}

/// How many characters [cleaned] holds, as the 2-letter floor counts them.
int searchTextLength(String cleaned) => cleaned.runes.length;
