import Link from 'next/link';
import { legalRoute } from '../lib/legal';

/// « {lead}, vous acceptez nos Conditions d’utilisation et notre Politique de
/// confidentialité. » — the twin of the app's `LegalConsentText`, both
/// documents LINKED (docs/design/web-pro-access.md §5). Shown before an
/// account can exist: the Pro sign-up (the salon contracts with us and uploads
/// identity documents), the Pro sign-in, the client sign-in.
///
/// Inline links in a sentence: WCAG 2.5.8's inline exception — a 48px box
/// would break the line; the underline distinguishes them from the text.
export function LegalConsentText({ lead }: { lead: string }) {
  const link = 'underline hover:text-textPrimary';
  return (
    <p className="text-bodySmall text-textTertiary">
      {lead}, vous acceptez nos{' '}
      <Link href={legalRoute('/cgu').slug} className={link}>
        Conditions d’utilisation
      </Link>{' '}
      et notre{' '}
      <Link href={legalRoute('/politique-confidentialite').slug} className={link}>
        Politique de confidentialité
      </Link>
      .
    </p>
  );
}
