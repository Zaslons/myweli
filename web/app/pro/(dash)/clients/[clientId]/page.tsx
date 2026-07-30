import type { Metadata } from 'next';
import { ClientCardClient } from '../../../../../components/pro/ClientCardClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Fiche client',
  robots: { index: false, follow: false },
};

export default function ProClientCardPage({
  params,
}: {
  params: { clientId: string };
}) {
  // B7 (§9/§10): the desktop cap — every state (skeleton, error,
  // success) shares it, so nothing flashes full-bleed then snaps.
  return (
    <div className="max-w-5xl">
      <ClientCardClient clientId={params.clientId} />
    </div>
  );
}
