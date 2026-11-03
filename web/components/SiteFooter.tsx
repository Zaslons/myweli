import Link from 'next/link';
import { LEGAL_ROUTES } from '../lib/legal';
import { SITE_CONTAINER } from '../lib/siteGrid';
import { SOCIAL_PROFILES } from '../lib/social';
import { Wordmark } from './brand/Wordmark';
import { FooterGroups } from './FooterGroups';
import { FooterMark } from './FooterMark';

/// The site footer (L1) — and the product's first `<footer>` landmark.
///
/// `WEB-SYSTEM.md` §4 has required `<header> <nav> <main> <footer>` since it was
/// written. There was none anywhere: `grep -rn "<footer" web/` returned a single
/// hit, a comment in `DataTable.tsx` about pagination. Neither register recorded
/// the rule as unmet, which is why L1 found it rather than a design slice.
///
/// **A server component, unlike `SiteChrome`.** That one is `'use client'`
/// because it needs `usePathname` to hide itself on `/pro`. Two parts of this one
/// depend on the page, and each is a client leaf: the logo (`FooterMark`) and the
/// groups (`FooterGroups`). This used to refuse a hydration boundary on every page
/// « to hide four links ». Apple's 3.1.1 refusal of build 698 is the reason that gave
/// way: the five pages the apps open have no salons' group, in the HTML as well as
/// on the screen (docs/design/app-review-round-2.md §5).
///
/// **And it does NOT hide on `/pro`.** `ProShell` is `min-h-screen lg:flex`, not
/// `h-screen overflow-hidden`, so a footer below it scrolls into view and breaks
/// no layout — and a professional needs the CGU *more* than a consumer does,
/// being the party that contracts with us and uploads identity documents.
///
/// Rendered from `app/layout.tsx` **after** `<div id="contenu">`, which is the
/// only place a site-wide footer can go: `SiteChrome` renders above the content.
///
/// The large wordmark and the three columns are the new look's
/// (docs/design/web-swiss-direction.md §3, §7.8).
export function SiteFooter() {
  return (
    <footer className="mt-xxl border-t border-primary">
      <div className={`${SITE_CONTAINER} py-xl lg:py-xxl`}>
        <FooterMark
          wordmark={
            <div className="lg:grid lg:grid-cols-12 lg:gap-x-l">
              <Wordmark />
            </div>
          }
        />
        <p className="mt-l text-bodyMedium text-textSecondary">
          MyWeli — réservation beauté &amp; bien-être en Côte d’Ivoire.
        </p>
        <FooterGroups
          legal={
            <ul>
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
          }
          /* The reciprocal half of `organizationJsonLd().sameAs` — same list,
             same URLs, enforced by `social.test.ts`. `rel="me"` is the
             microformat that says "this profile is also me", which is the
             human-readable statement `sameAs` makes to machines; declaring the
             profile in JSON-LD while never linking to it is the weaker half of
             one claim. `noopener noreferrer` follows the house idiom for
             external links. */
          social={
            <ul>
              {SOCIAL_PROFILES.map((profile) => (
                <li key={profile.url}>
                  <a
                    href={profile.url}
                    target="_blank"
                    rel="me noopener noreferrer"
                    className="inline-flex min-h-12 items-center text-bodyMedium text-textSecondary underline hover:text-textPrimary"
                  >
                    {profile.name}
                  </a>
                </li>
              ))}
            </ul>
          }
        />
      </div>
    </footer>
  );
}
