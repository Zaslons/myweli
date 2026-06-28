import type { Metadata } from 'next';
import { siteUrl } from './jsonld';

/// Site-wide metadata defaults. Pages override `title`/`description`/`alternates`
/// via their own `metadata` export, built on this base.
export const defaultMetadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: {
    default: 'Myweli — Réservation beauté en Côte d’Ivoire',
    template: '%s · Myweli',
  },
  description:
    'Trouvez et réservez votre salon de coiffure, barbier, onglerie ou spa ' +
    'en Côte d’Ivoire. Réservation en ligne, 24/7.',
  openGraph: {
    type: 'website',
    siteName: 'Myweli',
    locale: 'fr_FR',
    url: siteUrl,
  },
  twitter: { card: 'summary_large_image' },
};
