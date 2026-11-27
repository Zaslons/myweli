import { Fragment } from 'react';

import { emailSeams } from '../../lib/format';

const LEAD = 'Entrez le code reçu par e-mail à';

/// The sentence that says where a code went, with the address on a line of its
/// own (docs/design/web-code-sent-to.md; the app's `CodeSentTo`, SYSTEM.md
/// §13.3):
///
/// ```text
/// Entrez le code reçu par e-mail à
/// aminata.kone
/// @exemple.ci
/// ```
///
/// **Why not one sentence.** A browser never cuts inside a word, so inline after
/// « à », an address wider than the line did not break — it spilled: with
/// Android's text at 200 % on a 320 phone, « awa.kone.nouvelle@exemple.ci »
/// grew the page to 483 px. On its own line it breaks only at its seams
/// ([emailSeams], one `<wbr>` each); `break-words` cuts inside a piece only
/// when that piece alone is wider than the line, where no layout has more to
/// give. No period is drawn after it: on a line of its own, it would read as
/// part of the address.
///
/// The address is in ink, the sentence keeps its secondary colour. **A screen
/// reader hears one text, the sentence it always heard** — « Entrez le code reçu
/// par e-mail à aminata.kone@exemple.ci. » — from a visually hidden copy; the
/// drawing is hidden from it. Not the drawing itself: its runs and `<wbr>`s are
/// element boundaries, where a screen reader may stop and read the address in
/// pieces.
///
/// Used by both sign-ins' code step (`LoginOptions`, `ProLoginOptions`).
export function CodeSentTo({ email }: { email: string }) {
  const address = email.trim();
  return (
    <p className="text-bodyLarge">
      <span className="sr-only">{`${LEAD} ${address}.`}</span>
      <span aria-hidden="true">
        <span className="text-textSecondary">{LEAD}</span>
        <span className="block break-words text-textPrimary">
          {emailSeams(address).map((piece, i) => (
            <Fragment key={i}>
              {i > 0 ? <wbr /> : null}
              {piece}
            </Fragment>
          ))}
        </span>
      </span>
    </p>
  );
}
