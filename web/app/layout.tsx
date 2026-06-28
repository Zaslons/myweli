import type { ReactNode } from 'react';
import '../styles/globals.css';
import { SiteChrome } from '../components/SiteChrome';
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
        <SiteChrome />
        {children}
      </body>
    </html>
  );
}
