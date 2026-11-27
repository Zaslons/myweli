import { Fragment } from 'react';

import { emailSeams } from '../lib/format';

/// The drawing of an e-mail address that breaks only at its seams
/// (docs/design/web-email-seams.md, WEB-SYSTEM §9): a `<wbr>` before its « @ »
/// and before each « . » of its name part ([emailSeams]), never in the domain.
///
/// **The drawing only — never what a screen reader reads.** Chromium gives its
/// accessibility tree one text node per piece (« aminata », « .kone »,
/// « @exemple.ci »), and names a link drawn this way with a space at each
/// `<wbr>` (« support@ myweli.com », read off CDP on 2026-11-27). So the caller
/// hides it and gives a screen reader the address whole: [BreakableEmail] and
/// [EmailLink] do; a sentence that names an address does it for the whole
/// sentence (`CodeSentTo`, « Révoquer l’accès », « Alertes par e-mail »).
export function EmailSeams({ address }: { address: string }) {
  return (
    <>
      {emailSeams(address).map((piece, i) => (
        <Fragment key={i}>
          {i > 0 ? <wbr /> : null}
          {piece}
        </Fragment>
      ))}
    </>
  );
}

/// An address on its own: a roster cell, the Pro sidebar, a profile, a
/// dialog's subtitle.
///
/// A screen reader is given the address as one text (an `sr-only` copy); the
/// drawing is `aria-hidden`, cut at its seams. `break-words` is the fallback,
/// and only cuts inside a piece wider than a line by itself
/// (« ouattaraaminatakone »). **In a flex or grid item**, that item needs
/// `min-w-0` — pass it here when this span is the item:
/// `overflow-wrap: break-word` does not lower an item's min-content, so
/// without it the fallback cannot narrow the item, and the page grows.
export function BreakableEmail({ address, className = '' }: { address: string; className?: string }) {
  return (
    <span className={`break-words ${className}`.trim()}>
      <span className="sr-only">{address}</span>
      <span aria-hidden="true">
        <EmailSeams address={address} />
      </span>
    </span>
  );
}

/// A link that draws an address — the support address on the legal pages.
///
/// Named by its `aria-label`: the address, which is also its words
/// (WCAG 2.5.3). Its drawing is hidden from a screen reader, which would
/// otherwise also be given the pieces; and there is no second copy, because
/// these pages are public and their text is what search engines and AI
/// assistants read. The drawing is its own span with `min-w-0`, so a link laid
/// out as a flex row (`/support`) lets the fallback narrow it too.
export function EmailLink({
  address,
  href,
  className,
}: {
  address: string;
  href: string;
  className?: string;
}) {
  return (
    <a href={href} aria-label={address} className={className}>
      <span aria-hidden="true" className="min-w-0 break-words">
        <EmailSeams address={address} />
      </span>
    </a>
  );
}
