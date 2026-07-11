import type { Metadata } from 'next';
import { RevenusClient } from '../../../../components/pro/RevenusClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Revenus',
  robots: { index: false, follow: false },
};

export default function ProRevenusPage() {
  return <RevenusClient />;
}
