/// L1 — the legal documents' single source of truth.
///
/// Four pages, one date, one company block. The date is here rather than in each
/// page because four documents that each carried their own would drift the first
/// time one was amended — and a privacy policy dated later than the practice it
/// describes is worse than an undated one.
///
/// **`COMPANY` is where the RCCM lands — but it is NOT the only edit.** MyWeli
/// is not registered yet (owner decision, docs/design/legal-l1.md §12), so
/// `registration` says so plainly rather than leaving a blank that reads as an
/// oversight. This file used to claim registration was "one edit" here; it is
/// not — most of the surfaces are hard-coded prose in other documents. **The
/// number is deliberately not written here**: the first version of this fix
/// said "six" in three files while the manifest said "five", which is the same
/// stale-count defect one level out. The list — and what each becomes — is
/// `infra/legal/registration-manifest.json`, and
/// `tests/registration-claim.test.ts` prints it as a checklist the moment
/// `registered` is flipped.
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
///
/// **Bumped 2026-08-22**: the cookies section named Google as « la seule chose
/// qui ne vienne pas de nous », which was not true — « Continuer avec Apple »
/// loads a script from `appleid.cdn-apple.com` on the same terms. Apple is now
/// described rather than counted. Found by an audit, not by the page changing.
///
/// **Bumped 2026-08-21**: the cookies section now describes a page that only
/// contacts Google once the visitor chooses Google. It also repairs a breach of
/// the rule below — the 2026-08-20 rewrite of that same section (g_state named,
/// mobile added as a third Sentry surface, Termii disclosed, Twilio removed)
/// shipped WITHOUT bumping this constant, so for two days the page carried a
/// « Dernière mise à jour » and a JSON-LD `dateModified` that predated its own
/// substance. That is precisely the concealment reading this rule exists to
/// avoid, committed by the very change that wrote the rule down.
///
/// **Bumped 2026-08-18** for a substantive correction to the privacy policy: two
/// claims in « Ce que nous ne faisons pas » had become false and were replaced
/// by a « Journaux techniques et rapports d'erreur » section. The shared date
/// means the other three documents now show a date on which they did not
/// change — the accepted cost of one date. The alternative is worse: a privacy
/// policy whose substance moved while its date stood still is the version a
/// regulator reads as concealment.
export const LEGAL_UPDATED_AT = {
  iso: '2026-08-22',
  label: '22 août 2026',
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
  /// Mentions légales name the host; ours are three, in two jurisdictions.
  hosts: [
    'Google Cloud — serveurs applicatifs et base de données, Paris (France)',
    'Vercel Inc. — site web, États-Unis',
    'Cloudflare Inc. — stockage des fichiers (R2)',
  ],
} as const;
