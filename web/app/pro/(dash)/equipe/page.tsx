import type { Metadata } from 'next';
import { EquipeClient } from '../../../../components/pro/EquipeClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Équipe',
  robots: { index: false, follow: false },
};

export default function ProEquipePage() {
  return <EquipeClient />;
}
