import type { Metadata } from 'next';
import { RendezVousClient } from '../../../../components/pro/RendezVousClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Rendez-vous',
  robots: { index: false, follow: false },
};

export default function ProRendezVousPage() {
  return <RendezVousClient />;
}
