import Link from 'next/link';
import { LEGAL_ROUTES } from '../lib/legal';

/// The site footer (L1) — and the product's first `<footer>` landmark.
///
/// `WEB-SYSTEM.md` §4 has required `<header> <nav> <main> <footer>` since it was
/// written. There was none anywhere: `grep -rn "<footer" web/` returned a single
/// hit, a comment in `DataTable.tsx` about pagination. Neither register recorded
/// the rule as unmet, which is why L1 found it rather than a design slice.
///
/// **A server component, unlike `SiteChrome`.** That one is `'use client'`
/// because it needs `usePathname` to hide itself on `/pro`. This needs nothing
/// from the client, and making it a client component to gate on a pathname would
/// ship a hydration boundary on every page to hide four links.
///
/// **And it does NOT hide on `/pro`.** `ProShell` is `min-h-screen lg:flex`, not
/// `h-screen overflow-hidden`, so a footer below it scrolls into view and breaks
/// no layout — and a professional needs the CGU *more* than a consumer does,
/// being the party that contracts with us and uploads identity documents.
///
/// Rendered from `app/layout.tsx` **after** `<div id="contenu">`, which is the
/// only place a site-wide footer can go: `SiteChrome` renders above the content.
export function SiteFooter() {
  return (
    <footer className="mt-xxl border-t border-divider bg-secondary">
      <div className="mx-auto max-w-5xl px-m py-l">
        <p className="text-bodyMedium text-textSecondary">
          MyWeli — réservation beauté &amp; bien-être en Côte d’Ivoire.
        </p>
        <nav aria-label="Liens légaux" className="mt-s">
          <ul className="flex flex-wrap items-center gap-x-l">
            {LEGAL_ROUTES.map((r) => (
              <li key={r.slug}>
                <Link
                  href={r.slug}
                  // `min-h-12` is §13.2's 48px floor, and `underline` keeps
                  // axe's `link-in-text-block` quiet — a link distinguished by
                  // colour alone is the realistic new violation here, and these
                  // sit in a paragraph-coloured block.
                  className="inline-flex min-h-12 items-center text-bodyMedium text-textSecondary underline hover:text-textPrimary"
                >
                  {r.footerLabel}
                </Link>
              </li>
            ))}
          </ul>
        </nav>
      </div>
    </footer>
  );
}
