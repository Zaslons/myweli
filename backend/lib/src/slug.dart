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

/// Public URL slugs a salon may NEVER claim (multi-pays MP1): the web's
/// taxonomy roots, the seeded city slugs and the web app's own top-level
/// routes all share the `/[slug]` namespace with provider pages — a salon
/// named « Coiffure » must never shadow `/coiffure`. Salon slug generation
/// uniquifies past these. Kept in sync with `web/lib/landing.ts` +
/// `web/lib/service-landing.ts` (taxonomy) and the localities seed (city
/// slugs — pinned by a test against `seedCities`).
const Set<String> reservedPublicSlugs = {
  // Category landing roots (web/lib/landing.ts).
  'coiffure', 'barbier', 'onglerie', 'spa', 'massage',
  // Curated service landing roots (web/lib/service-landing.ts).
  'tresses', 'tissage', 'defrisage', 'coupe-homme', 'barbe', 'coupe-femme',
  'locks', 'coloration', 'manucure', 'pedicure', 'ongles', 'soin-visage',
  // Web top-level routes + API roots sharing the namespace.
  'recherche', 'connexion', 'mon-compte', 'pro', 'api', 'localities',
  'sitemap', 'robots',
  // Seeded city slugs (the nested landing tree /<taxo>/<ville>/<commune>).
  'abidjan',
};

bool isReservedSlug(String slug) => reservedPublicSlugs.contains(slug);
