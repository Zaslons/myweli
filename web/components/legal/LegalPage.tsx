import type { Metadata } from 'next';
import Link from 'next/link';
import { Children, type ReactNode } from 'react';
import {
  type DocumentDate,
  type DocumentRoute,
  LEGAL_UPDATED_AT,
  legalRoute,
} from '../../lib/legal';
import { breadcrumbJsonLd, siteUrl, webPageJsonLd } from '../../lib/seo/jsonld';
import { SUPPORT, supportMailto } from '../../lib/support';
import { ButtonLink } from '../ButtonLink';
import { JsonLd } from '../JsonLd';

/// The shell every legal document renders through (L1), and **the only file in
/// this feature that contains a `className`**.
///
/// That is not tidiness. The Tailwind theme is closed and `no-custom-classname`
/// is an error — but Tailwind **emits nothing for an unknown utility rather than
/// failing**, so a typo does not break the build: it ships an unstyled legal page
/// with `tsc`, lint and every test green. Concentrating the classes here gives
/// that failure one place to hide instead of five, and gives review one file to
/// read.
///
/// Layout copied from `components/landing/TaxonomyLandingView.tsx`, including
/// its (unexported, so duplicated) breadcrumb: `max-w-content` is SYSTEM §10's
/// 720px cap — *"a 1000px-wide line of French body copy is unreadable"* — and
/// `text-bodyLarge` is B8's rule that French reading copy is 16.
///
/// **Two layers since B0.19** (docs/design/web-pro-account-deletion.md §7).
/// `DocumentPage` and `documentMetadata` take a route and a date as arguments;
/// `LegalPage` and `legalMetadata` are one-line wrappers that pass a
/// `LEGAL_ROUTES` entry and `LEGAL_UPDATED_AT`, so the four legal documents
/// render byte-identical to before. `/pro/suppression-compte` renders through
/// `DocumentPage` with its own route and its own date: it is not one of the
/// four, and the shared legal date must never move it (nor it, the date).

export function documentMetadata(r: DocumentRoute): Metadata {
  return {
    title: r.title,
    description: r.description,
    alternates: { canonical: r.slug },
    openGraph: {
      title: r.title,
      description: r.description,
      url: `${siteUrl}${r.slug}`,
    },
  };
}

export function legalMetadata(slug: string): Metadata {
  return documentMetadata(legalRoute(slug));
}

export function LegalPage({
  slug,
  children,
  extraJsonLd,
}: {
  slug: string;
  children: ReactNode;
  extraJsonLd?: unknown;
}) {
  return (
    <DocumentPage route={legalRoute(slug)} updatedAt={LEGAL_UPDATED_AT} extraJsonLd={extraJsonLd}>
      {children}
    </DocumentPage>
  );
}

/// The shell itself. Its date is an argument, never `LEGAL_UPDATED_AT`: the
/// JSON-LD `dateModified` and the visible « Dernière mise à jour » both come
/// from `updatedAt`, so they cannot disagree with each other either.
export function DocumentPage({
  route: r,
  updatedAt,
  children,
  extraJsonLd,
}: {
  route: DocumentRoute;
  updatedAt: DocumentDate;
  children: ReactNode;
  extraJsonLd?: unknown;
}) {
  return (
    <main className="mx-auto max-w-content px-m py-l">
      <JsonLd
        data={webPageJsonLd({
          name: r.h1,
          path: r.slug,
          description: r.description,
          dateModified: updatedAt.iso,
        })}
      />
      <JsonLd
        data={breadcrumbJsonLd([
          { name: 'Accueil', url: `${siteUrl}/` },
          { name: r.h1, url: `${siteUrl}${r.slug}` },
        ])}
      />
      {extraJsonLd ? <JsonLd data={extraJsonLd} /> : null}

      <nav aria-label="Fil d’Ariane" className="text-bodyMedium text-textSecondary">
        <ol className="flex flex-wrap items-center gap-xs">
          <li>
            <Link href="/" className="underline hover:text-textPrimary">
              Accueil
            </Link>
          </li>
          <li className="flex items-center gap-xs">
            <span aria-hidden>›</span>
            <span aria-current="page" className="text-textPrimary">
              {r.h1}
            </span>
          </li>
        </ol>
      </nav>

      <h1 className="mt-m text-headlineMedium font-semibold text-textPrimary">
        {r.h1}
      </h1>
      <p className="mt-s text-bodyMedium text-textSecondary">
        Dernière mise à jour : {updatedAt.label}
      </p>

      {children}
    </main>
  );
}

/// A section heading. `<h2>` only — WEB-SYSTEM §4: heading levels never skip,
/// and a legal document that needs `<h3>` needs shorter sections instead.
export function H2({ children }: { children: ReactNode }) {
  return (
    <h2 className="mt-l text-titleLarge font-semibold text-textPrimary">
      {children}
    </h2>
  );
}

export function P({ children }: { children: ReactNode }) {
  return <p className="mt-m text-bodyLarge text-textSecondary">{children}</p>;
}

/// Emphasised lead-in — the one-sentence answer above a section's detail.
export function Lead({ children }: { children: ReactNode }) {
  return <p className="mt-m text-bodyLarge text-textPrimary">{children}</p>;
}

export function Ul({ children }: { children: ReactNode }) {
  return (
    <ul className="mt-m flex flex-col gap-s text-bodyLarge text-textSecondary">
      {children}
    </ul>
  );
}

export function Li({ children }: { children: ReactNode }) {
  return <li className="flex gap-s">
    <span aria-hidden className="text-textTertiary">
      —
    </span>
    <span>{children}</span>
  </li>;
}

/// `Li` for `/pro/suppression-compte`, the one document gated at doubled text
/// on a 320 phone (web-pro-account-deletion.md §4.4, §10 #14). In `Li` the
/// text is a flex item, so its width can never fall below its longest word:
/// at 32px « automatiquement&nbsp;; » is 277px beside a 248px column, and the
/// Android mode grew the page to 335px. Here the text may shrink (`min-w-0`)
/// and the word hyphenates (`hyphens-auto`, `lang="fr"`), or breaks where a
/// browser has no French hyphenation (`break-words`) — the 404's remedy in
/// web-funnel-doubled-text.md §5. `Li` itself is unchanged: it renders on the
/// frozen five.
export function Item({ children }: { children: ReactNode }) {
  return (
    <li className="flex gap-s">
      <span aria-hidden className="text-textTertiary">
        —
      </span>
      <span className="min-w-0 break-words hyphens-auto">{children}</span>
    </li>
  );
}

export function A({ href, children }: { href: string; children: ReactNode }) {
  return (
    <Link href={href} className="underline hover:text-textPrimary">
      {children}
    </Link>
  );
}

/// A bordered aside for the one thing on a page that must not be missed.
export function Callout({ children }: { children: ReactNode }) {
  return (
    <div className="mt-l rounded-xl border border-border bg-secondary p-m">
      {children}
    </div>
  );
}

/// A numbered list of steps (`/pro/suppression-compte`'s « Sur le web »), each
/// `Step` one item. The number is drawn, in `Item`'s shape (a flex row, the
/// number where the dash is, the text free to shrink: `min-w-0`), and `Ol`
/// writes it from the step's place, so it cannot drift from the order. No
/// `hyphens-auto`, unlike `Item`: the steps name the buttons to press, and
/// « Conti-nuer avec Google » is harder to find on screen. `break-words` breaks
/// a word only when it cannot fit a line at all.
///
/// Not the browser's `list-decimal` marker: that marker grows with the text
/// while a list's padding does not, so at doubled text (Android, 320) « 1. »
/// stuck out of its 24px `pl-l` into the 16px gutter, 6px from the screen's
/// edge, and no sideways scroll gave it away (`type-overflow.spec.ts`, the
/// page's doubled-text run). Hidden from a screen reader, as on
/// `/professionnels`: the `<ol>` gives the count and the order.
export function Ol({ children }: { children: ReactNode }) {
  return (
    <ol className="mt-m flex flex-col gap-s text-bodyLarge text-textSecondary">
      {Children.toArray(children).map((step, i) => (
        <li key={i} className="flex gap-s">
          <span aria-hidden>{i + 1}.</span>
          <div className="min-w-0 break-words">{step}</div>
        </li>
      ))}
    </ol>
  );
}

/// One step of an `Ol`, which draws its item and its number.
export function Step({ children }: { children: ReactNode }) {
  return <>{children}</>;
}

/// The one action a document may carry: a link that looks like a button
/// (`ButtonLink`, primary, `min-h-12` — SYSTEM §13.2's 48px). No `nowrap`, so a
/// long label wraps at 320px instead of spilling.
export function Cta({ href, children }: { href: string; children: ReactNode }) {
  return (
    <div className="mt-s">
      <ButtonLink href={href}>{children}</ButtonLink>
    </div>
  );
}

/// The support address, printed. Its text breaks after « @ » (`<wbr>`): at
/// doubled text « support@myweli.com » is one unbreakable word wider than a
/// 320px column, which is what widens `/mentions-legales` to 343px (WEB-SYSTEM
/// §15 row 38). `supportMailto()` with no subject, as `/mentions-legales`
/// calls it. The shared `A` is left alone: it renders on the frozen five.
export function Email() {
  const [user, domain] = SUPPORT.email.split('@');
  return (
    <a href={supportMailto()} className="underline hover:text-textPrimary">
      {user}@<wbr />
      {domain}
    </a>
  );
}
