import type { Metadata } from 'next';
import { DisponibilitesClient } from '../../../../components/pro/DisponibilitesClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Disponibilités',
  robots: { index: false, follow: false },
};

export default function ProDisponibilitesPage() {
  // B7 (§9/§10): the desktop cap — every state (skeleton, error,
  // success) shares it, so nothing flashes full-bleed then snaps.
  return (
    <div className="max-w-content">
      <DisponibilitesClient />
    </div>
  );
}
