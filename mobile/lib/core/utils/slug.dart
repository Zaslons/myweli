/// The backend's `slugify` in the app — its twin, rule for rule
/// (backend/lib/src/slug.dart; the website's is web/lib/slug.ts). Pure and
/// deterministic.
///
/// Its use here is R8 (docs/design/salon-go-live-approval.md §6.3,
/// decision 136 item 4): the server's publish gate takes a commune typed by
/// hand only when it names one of MyWeli's areas by slug
/// (`seedAreaForCommuneName`: `slugify(commune)` equals the area's `slug`, or
/// `slugify` of its name), so « Configuration » must slug it the same way to
/// say what the server will say. `test/unit/slug_twin_test.dart` reads the
/// backend file and fails on any drift — an accent added there and not here
/// would tick « Profil de l’entreprise » for a commune the server refuses.
library;

const Map<String, String> kSlugAccents = {
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'á': 'a',
  'ã': 'a',
  'å': 'a',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'œ': 'oe',
  'æ': 'ae',
};

/// Lowercase, deaccent, drop non-alphanumerics → single hyphens, trimmed.
/// e.g. « Beauté Divine » → `beaute-divine`, « Nails & Co » → `nails-co`.
String slugify(String input) {
  final lower = input.toLowerCase();
  final deaccented = lower.split('').map((c) => kSlugAccents[c] ?? c).join();
  final hyphenated = deaccented.replaceAll(RegExp('[^a-z0-9]+'), '-');
  return hyphenated.replaceAll(RegExp('^-+|-+\$'), '');
}
