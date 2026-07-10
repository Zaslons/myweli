import type { Metadata } from 'next';
import { AvisClient } from '../../../../components/pro/AvisClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Avis',
  robots: { index: false, follow: false },
};

export default function ProAvisPage() {
  return <AvisClient />;
}
