import type { Metadata } from 'next';
import { AccountClient } from '../../components/account/AccountClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Mon compte',
  robots: { index: false, follow: false },
};

export default function MonComptePage() {
  return (
    <main className="mx-auto max-w-2xl px-m py-l">
      <h1 className="text-headlineSmall font-semibold text-textPrimary">Mon compte</h1>
      <div className="mt-l">
        <AccountClient />
      </div>
    </main>
  );
}
