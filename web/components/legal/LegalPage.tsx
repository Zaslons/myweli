import type { Metadata } from 'next';
import Link from 'next/link';
import type { ReactNode } from 'react';
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

/// A numbered list of steps (`/pro/suppression-compte`'s « Sur le web »). The
/// browser's own numbers, outside the text (`list-outside`, the default), so a
/// step that wraps keeps its number in the margin; `pl-l` makes the room.
export function Ol({ children }: { children: ReactNode }) {
  return (
    <ol className="mt-m flex list-decimal flex-col gap-s pl-l text-bodyLarge text-textSecondary">
      {children}
    </ol>
  );
}

export function Step({ children }: { children: ReactNode }) {
  return <li>{children}</li>;
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
