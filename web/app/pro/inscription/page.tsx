import type { Metadata } from 'next';
import { ProRegisterClient } from '../../../components/pro/ProRegisterClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'MyWeli Pro — Créer un compte',
  robots: { index: false, follow: false },
};

export default function ProInscriptionPage() {
  return (
    <main className="mx-auto max-w-2xl px-m py-xl">
      <ProRegisterClient />
    </main>
  );
}
