import type { Metadata } from 'next';
import { CatalogueClient } from '../../../../components/pro/CatalogueClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Catalogue',
  robots: { index: false, follow: false },
};

export default function ProCataloguePage() {
  // B7 (§9/§10): the desktop cap — every state (skeleton, error,
  // success) shares it, so nothing flashes full-bleed then snaps.
  return (
    <div className="max-w-5xl">
      <CatalogueClient />
    </div>
  );
}
