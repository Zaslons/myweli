import type { Metadata } from 'next';
import { VerificationClient } from '../../../../components/pro/VerificationClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Vérification',
  robots: { index: false, follow: false },
};

export default function ProVerificationPage() {
  return <VerificationClient />;
}
