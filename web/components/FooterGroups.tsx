'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import type { ReactNode } from 'react';
import { isStoreLinkedPage } from '../lib/storeLinkedPages';

/// The salons' footer group (docs/design/web-pro-access.md P2) — the door a
/// phone reaches, where the header's « Espace pro » does not fit.
const PRO_LINKS = [
  { label: 'MyWeli Pro pour les salons', href: '/professionnels' },
  { label: 'Inscrire mon salon', href: '/pro/inscription' },
  { label: 'Connexion Espace pro', href: '/pro/connexion' },
] as const;

/// The footer's three groups, and the page-dependent part of them: the five pages the
/// apps open have no salons' group (docs/design/app-review-round-2.md §5).
///
/// **The list lives here, and never comes in as a prop.** A rendered group handed to a
/// client component is serialized into the page's RSC payload: nothing on the screen, and
/// `/pro/inscription` in the HTML of the page that claims not to have it. The legal and
/// social lists are the opposite, on every page and rendered on the server, so they do
/// come in as props and stay out of the client bundle.
///
/// **All three sit here because the drop follows the title.** The legal and social groups
/// have no visible title, so from `lg` they drop by the height of the salons' one, and all
/// three lists start on one line. With no title beside them the drop would be a stray gap.
/// Without the group the two keep their columns, so the footer stays on the site's grid
/// and the third column is empty. Below `lg` the first group's `mt-m` collapses into its
/// parent's, so a phone gets no gap either.
export function FooterGroups({ legal, social }: { legal: ReactNode; social: ReactNode }) {
  const withSalons = !isStoreLinkedPage(usePathname() ?? '');
  const group = withSalons ? 'mt-m lg:col-span-4 lg:mt-0 lg:pt-xxl' : 'mt-m lg:col-span-4 lg:mt-0';
  return (
    <div className="mt-m lg:grid lg:grid-cols-12 lg:gap-x-l">
      {withSalons ? (
        <nav aria-labelledby="footer-pro" className="lg:col-span-4">
          <p
            id="footer-pro"
            className="flex min-h-12 items-center text-bodyMedium font-medium text-textPrimary"
          >
            Professionnels
          </p>
          <ul>
            {PRO_LINKS.map((l) => (
              <li key={l.href}>
                <Link
                  href={l.href}
                  className="inline-flex min-h-12 items-center text-bodyMedium text-textSecondary underline hover:text-textPrimary"
                >
                  {l.label}
                </Link>
              </li>
            ))}
          </ul>
        </nav>
      ) : null}
      <nav aria-label="Liens légaux" className={group}>
        {legal}
      </nav>
      <nav aria-label="Réseaux sociaux" className={group}>
        {social}
      </nav>
    </div>
  );
}
