import type { ReactNode } from 'react';
import '../styles/globals.css';
import { SiteChrome } from '../components/SiteChrome';
import { SiteFooter } from '../components/SiteFooter';
import { jsonLdScript, organizationJsonLd } from '../lib/seo/jsonld';
import { defaultMetadata } from '../lib/seo/metadata';

export const metadata = defaultMetadata;

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="fr">
      <body>
        {/* Brand entity (GEO) — emitted site-wide. */}
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{
            __html: jsonLdScript(organizationJsonLd()),
          }}
        />
        {/* §5: the FIRST focusable element on every page. sr-only until focused —
            the first Tab reveals it wearing the new ring, which is also the
            ring's most visible proof. `<main>` lives per-page in 14 files, so
            the layout-level #contenu wrapper is the one-edit jump target and
            covers the pro shell for free. */}
        <a
          href="#contenu"
          className="sr-only focus:not-sr-only focus:absolute focus:left-m focus:top-m focus:z-toast focus:rounded-lg focus:bg-secondary focus:p-m focus:text-labelLarge focus:text-textPrimary"
        >
          Aller au contenu
        </a>
        <SiteChrome />
        <div id="contenu">{children}</div>
        {/* §4's fourth landmark, and the product's first. It must sit AFTER the
            content — `SiteChrome` renders above it — and it is unconditional:
            see the component for why `/pro` gets one too. */}
        <SiteFooter />
      </body>
    </html>
  );
}
