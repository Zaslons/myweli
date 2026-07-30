import type { Metadata } from 'next';
import { DataExportClient } from '../../../components/account/DataExportClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Mes données',
  robots: { index: false, follow: false },
};

export default function DonneesPage() {
  return (
    <main className="mx-auto max-w-2xl px-m py-l">
      <DataExportClient />
    </main>
  );
}
