import type { Metadata } from 'next';
import { RevenusClient } from '../../../../components/pro/RevenusClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Revenus',
  robots: { index: false, follow: false },
};

export default function ProRevenusPage() {
  // B7 (§9/§10): the desktop cap — every state (skeleton, error,
  // success) shares it, so nothing flashes full-bleed then snaps.
  return (
    <div className="max-w-content">
      <RevenusClient />
    </div>
  );
}
