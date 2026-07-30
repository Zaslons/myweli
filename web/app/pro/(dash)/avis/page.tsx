import type { Metadata } from 'next';
import { AvisClient } from '../../../../components/pro/AvisClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Avis',
  robots: { index: false, follow: false },
};

export default function ProAvisPage() {
  // B7 (§9/§10): the desktop cap — every state (skeleton, error,
  // success) shares it, so nothing flashes full-bleed then snaps.
  return (
    <div className="max-w-3xl">
      <AvisClient />
    </div>
  );
}
