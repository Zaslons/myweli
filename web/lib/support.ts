/// Support: the address that reaches a person, and the channels the page shows.
///
/// **A constant, not a Vercel variable**, for the same reason `COMPANY` in
/// `legal.ts` is one: it is a published fact about the business, it belongs in a
/// PR where someone can see it change, and a test can hold the page to it. An
/// env var here would be invisible to review and unverifiable from CI — and this
/// is the address both stores print on a listing page.
///
/// `no-reply@myweli.com` is the send-only sender for transactional mail and must
/// never be offered as a contact; `legal-l1.md` §"open" recorded that gap, and
/// this closes it.
export const SUPPORT = {
  email: 'support@myweli.com',
  /// The page every surface points at — the app's « Aide & Support », both store
  /// listings' support field, and the mentions légales.
  path: '/support',
} as const;

/// Support entry (parity 15.2): the manual-intake WhatsApp channel
/// (docs: disputes are admin-resolved; intake is WhatsApp support).
/// Number filled at the accounts phase via NEXT_PUBLIC_MYWELI_WHATSAPP —
/// same env as the pro « Nous contacter » CTA.
///
/// **Returns null when the number is unset**, so a caller renders nothing
/// rather than a link. It used to interpolate an empty string into
/// `https://wa.me/?text=…` — a link that goes to WhatsApp's own landing page,
/// which is worse than no link because it looks like it worked.
///
/// It is no longer the *only* channel: WhatsApp is gated on company
/// registration, so `SUPPORT.email` carries the page until the number exists.
export function supportWhatsAppUrl(): string | null {
  const number = process.env.NEXT_PUBLIC_MYWELI_WHATSAPP ?? '';
  if (!number) return null;
  const text = encodeURIComponent(
    'Bonjour MyWeli, j’ai besoin d’aide concernant mon compte.',
  );
  return `https://wa.me/${number}?text=${text}`;
}

/// `mailto:` with a subject, so an inbox can be triaged without asking.
export function supportMailto(subject?: string): string {
  const q = subject ? `?subject=${encodeURIComponent(subject)}` : '';
  return `mailto:${SUPPORT.email}${q}`;
}
