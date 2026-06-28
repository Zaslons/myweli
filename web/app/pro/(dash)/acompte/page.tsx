import type { Metadata } from 'next';
import { AcompteClient } from '../../../../components/pro/AcompteClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Acompte',
  robots: { index: false, follow: false },
};

export default function ProAcomptePage() {
  return <AcompteClient />;
}
