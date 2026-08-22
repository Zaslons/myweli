/// Support entry (parity 15.2): the manual-intake WhatsApp channel
/// (docs: disputes are admin-resolved; intake is WhatsApp support).
/// Number filled at the accounts phase via NEXT_PUBLIC_MYWELI_WHATSAPP —
/// same env as the pro « Nous contacter » CTA.
///
/// **Returns null when the number is unset**, so a caller renders nothing
/// rather than a link. It used to interpolate an empty string into
/// `https://wa.me/?text=…` — a link that goes to WhatsApp's own landing page,
/// which is worse than no link because it looks like it worked. The Flutter app
/// has always degraded properly here (« Contact bientôt disponible. »); web was
/// the surface that did not, and the number is currently unset in every build.
export function supportWhatsAppUrl(): string | null {
  const number = process.env.NEXT_PUBLIC_MYWELI_WHATSAPP ?? '';
  if (!number) return null;
  const text = encodeURIComponent(
    'Bonjour MyWeli, j’ai besoin d’aide concernant mon compte.',
  );
  return `https://wa.me/${number}?text=${text}`;
}
