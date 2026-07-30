/// Support entry (parity 15.2): the manual-intake WhatsApp channel
/// (docs: disputes are admin-resolved; intake is WhatsApp support).
/// Number filled at the accounts phase via NEXT_PUBLIC_MYWELI_WHATSAPP —
/// same env as the pro « Nous contacter » CTA.
export function supportWhatsAppUrl(): string {
  const number = process.env.NEXT_PUBLIC_MYWELI_WHATSAPP ?? '';
  const text = encodeURIComponent(
    'Bonjour MyWeli, j’ai besoin d’aide concernant mon compte.',
  );
  return `https://wa.me/${number}?text=${text}`;
}
