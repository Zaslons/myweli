import type { ReactNode } from 'react';
import '../styles/globals.css';
import { AppInstallBanner } from '../components/AppInstallBanner';
import { Header } from '../components/Header';
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
        <AppInstallBanner />
        <Header />
        {children}
      </body>
    </html>
  );
}
