// URL slug helper for provider public pages (myweli.ci/<slug>).
// Pure + deterministic. Design: docs/design/web-m1-backend-glue.md.

const _accents = {
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
/// e.g. "Beauté Divine" → "beaute-divine", "Nails & Co" → "nails-co".
String slugify(String input) {
  final lower = input.toLowerCase();
  final deaccented = lower.split('').map((c) => _accents[c] ?? c).join();
  final hyphenated = deaccented.replaceAll(RegExp('[^a-z0-9]+'), '-');
  return hyphenated.replaceAll(RegExp('^-+|-+\$'), '');
}
