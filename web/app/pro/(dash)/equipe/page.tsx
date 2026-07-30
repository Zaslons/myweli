import type { Metadata } from 'next';
import { EquipeClient } from '../../../../components/pro/EquipeClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Équipe',
  robots: { index: false, follow: false },
};

export default function ProEquipePage() {
  // B7 (§9/§10): the desktop cap — every state (skeleton, error,
  // success) shares it, so nothing flashes full-bleed then snaps.
  return (
    <div className="max-w-5xl">
      <EquipeClient />
    </div>
  );
}
