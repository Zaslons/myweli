import type { Metadata } from 'next';
import { DisponibilitesClient } from '../../../../components/pro/DisponibilitesClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Disponibilités',
  robots: { index: false, follow: false },
};

export default function ProDisponibilitesPage() {
  return <DisponibilitesClient />;
}
