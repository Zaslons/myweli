import type { Metadata } from 'next';
import { ProfilClient } from '../../../../components/pro/ProfilClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Profil',
  robots: { index: false, follow: false },
};

export default function ProProfilPage() {
  return <ProfilClient />;
}
