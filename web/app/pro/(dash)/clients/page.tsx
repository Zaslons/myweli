import type { Metadata } from 'next';
import { ClientsClient } from '../../../../components/pro/ClientsClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Clients',
  robots: { index: false, follow: false },
};

export default function ProClientsPage() {
  // B7 (§9/§10): the desktop cap — every state (skeleton, error,
  // success) shares it, so nothing flashes full-bleed then snaps.
  return (
    <div className="max-w-5xl">
      <ClientsClient />
    </div>
  );
}
