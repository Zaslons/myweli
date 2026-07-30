import type { Metadata } from 'next';
import { AddSalonClient } from '../../../../../components/pro/AddSalonClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Ajouter un salon',
  robots: { index: false, follow: false },
};

export default function ProAddSalonPage() {
  return <AddSalonClient />;
}
