/// L1 — the legal documents' single source of truth.
///
/// Four pages, one date, one company block. The date is here rather than in each
/// page because four documents that each carried their own would drift the first
/// time one was amended — and a privacy policy dated later than the practice it
/// describes is worse than an undated one.
///
/// **`COMPANY` is where the RCCM lands as one edit.** MyWeli is not registered
/// yet (owner decision, docs/design/legal-l1.md §12), so `registration` says so
/// plainly rather than leaving a blank that reads as an oversight.
///
/// **`LEGAL_ROUTES` is half of a cross-surface contract.** `AppConfig.privacyUrl`
/// and its three siblings build these exact paths into the mobile binary, and
/// **no mobile test can reach the web** — so this list and
/// `mobile/lib/core/config/app_config.dart` are reviewed together, in one PR.
/// `tests/legal.test.tsx` pins the slugs so at least the web half cannot move
/// silently.
///
/// Consumed by: the four `app/*/page.tsx`, `components/SiteFooter.tsx`,
/// `app/sitemap.ts`, and `backend/lib/src/slug.dart`'s `reservedPublicSlugs`
/// (which must contain all four, or a salon can take `/cgu` and be shadowed by
/// the static route).

export type LegalRoute = {
  /// Absolute path, leading slash, no trailing slash.
  readonly slug: string;
  /// The page's `<h1>` — its core entity (WEB-SYSTEM §4).
  readonly h1: string;
  /// The `<title>`, which `defaultMetadata`'s template suffixes with « · MyWeli ».
  readonly title: string;
  readonly description: string;
  /// Shown in the footer, where « Politique de confidentialité » is too long to
  /// sit beside three siblings on a 375px phone.
  readonly footerLabel: string;
};

export const LEGAL_ROUTES: readonly LegalRoute[] = [
  {
    slug: '/politique-confidentialite',
    h1: 'Politique de confidentialité',
    title: 'Politique de confidentialité',
    description:
      'Quelles données MyWeli traite, pourquoi, avec qui elles sont partagées, ' +
      'et comment les consulter, les exporter ou les supprimer.',
    footerLabel: 'Politique de confidentialité',
  },
  {
    slug: '/cgu',
    h1: 'Conditions générales d’utilisation',
    title: 'Conditions générales d’utilisation',
    description:
      'Les règles d’utilisation de MyWeli : le rôle d’intermédiaire, les ' +
      'acomptes, les annulations, les avis et les responsabilités de chacun.',
    footerLabel: 'Conditions d’utilisation',
  },
  {
    slug: '/mentions-legales',
    h1: 'Mentions légales',
    title: 'Mentions légales',
    description:
      'Éditeur, directeur de la publication, hébergeurs et propriété ' +
      'intellectuelle du service MyWeli.',
    footerLabel: 'Mentions légales',
  },
  {
    slug: '/suppression-compte',
    h1: 'Supprimer votre compte',
    title: 'Supprimer votre compte',
    description:
      'Comment supprimer votre compte MyWeli, et exactement ce qui est ' +
      'supprimé, anonymisé ou conservé.',
    footerLabel: 'Supprimer mon compte',
  },
] as const;

export function legalRoute(slug: string): LegalRoute {
  const found = LEGAL_ROUTES.find((r) => r.slug === slug);
  if (!found) throw new Error(`unknown legal route: ${slug}`);
  return found;
}

/// One date for all four documents.
///
/// `iso` feeds `dateModified` in the JSON-LD; `label` is what a human reads.
/// Written out rather than formatted at render time, because a page rendered at
/// build time and a page rendered on request must not disagree — and because a
/// legal document's date is a claim, not a timestamp.
export const LEGAL_UPDATED_AT = {
  iso: '2026-07-27',
  label: '27 juillet 2026',
} as const;

export const COMPANY = {
  tradingName: 'MyWeli',
  /// No RCCM yet — the honest statement, not a blank.
  registration:
    'société en cours d’immatriculation au Registre du Commerce et du Crédit ' +
    'Mobilier de Côte d’Ivoire',
  /// Filled at registration; until then the page says so rather than inventing.
  pendingFacts: [
    'numéro RCCM',
    'siège social',
    'capital social',
    'numéro de compte contribuable',
    'représentant légal',
  ],
  country: 'Côte d’Ivoire',
  /// Mentions légales name the host; ours are three, in two jurisdictions.
  hosts: [
    'Render Inc. — serveurs applicatifs et base de données, Francfort (Allemagne)',
    'Vercel Inc. — site web, États-Unis',
    'Cloudflare Inc. — stockage des fichiers (R2)',
  ],
} as const;
