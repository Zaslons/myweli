/// The brand's public social profiles — one list, two consumers.
///
/// **A constant, not a Vercel variable**, for the reason `SUPPORT` in
/// `support.ts` and `COMPANY` in `legal.ts` are constants: these are published
/// facts about the business, they belong in a PR where someone can see them
/// change, and a test can hold both consumers to them. An env var here would be
/// invisible to review and unverifiable from CI.
///
/// The two consumers must agree, and `social.test.ts` fails if they drift:
///
///   `organizationJsonLd().sameAs`  the entity claim, read by machines
///   `SiteFooter`                   the reciprocal link, read by people
///
/// The reciprocity is not decoration. `sameAs` asserts "this site and that
/// profile are one entity"; an engine weighs that assertion far more when the
/// site actually links to the profile. Declaring a profile the site never
/// mentions is the weaker half of the same claim.
///
/// **Canonical URLs only — no query string, no fragment.** The Instagram URL
/// arrives from the app's share sheet as
/// `https://www.instagram.com/myweli_?igsi=<token>`; `igsi` identifies the
/// share, not the profile. Carrying it into `sameAs` would publish a
/// per-share token as the brand's permanent identifier, and into the footer
/// would attribute every visitor to one share. The test enforces the shape
/// rather than trusting whoever pastes the next one.
export const SOCIAL_PROFILES = [
  {
    /// `myweli_` — the trailing underscore is part of the handle. Verified
    /// 2026-08-24 in a real browser: the page titles itself
    /// « Myweli (@myweli_) », where a handle that does not exist titles itself
    /// « Profile isn't available ». `curl` cannot tell them apart — Instagram
    /// serves both a 200 and a JS shell — so a status-code check is not a
    /// check here.
    name: 'Instagram',
    url: 'https://www.instagram.com/myweli_/',
  },
] as const;
