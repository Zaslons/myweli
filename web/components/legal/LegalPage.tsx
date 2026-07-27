import type { Metadata } from 'next';
import Link from 'next/link';
import type { ReactNode } from 'react';
import { LEGAL_UPDATED_AT, legalRoute } from '../../lib/legal';
import { breadcrumbJsonLd, siteUrl, webPageJsonLd } from '../../lib/seo/jsonld';
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

export function legalMetadata(slug: string): Metadata {
  const r = legalRoute(slug);
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

export function LegalPage({
  slug,
  children,
  extraJsonLd,
}: {
  slug: string;
  children: ReactNode;
  extraJsonLd?: unknown;
}) {
  const r = legalRoute(slug);
  return (
    <main className="mx-auto max-w-content px-m py-l">
      <JsonLd
        data={webPageJsonLd({
          name: r.h1,
          path: r.slug,
          description: r.description,
          dateModified: LEGAL_UPDATED_AT.iso,
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
        Dernière mise à jour : {LEGAL_UPDATED_AT.label}
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
