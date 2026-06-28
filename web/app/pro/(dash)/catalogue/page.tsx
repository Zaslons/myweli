import type { Metadata } from 'next';
import { CatalogueClient } from '../../../../components/pro/CatalogueClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Catalogue',
  robots: { index: false, follow: false },
};

export default function ProCataloguePage() {
  return <CatalogueClient />;
}
