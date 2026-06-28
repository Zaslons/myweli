import type { Metadata } from 'next';
import { AbonnementClient } from '../../../../components/pro/AbonnementClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Abonnement',
  robots: { index: false, follow: false },
};

export default function ProAbonnementPage() {
  return <AbonnementClient />;
}
