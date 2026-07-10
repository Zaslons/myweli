import type { Metadata } from 'next';
import { Suspense } from 'react';
import { ConnexionClient } from '../../components/auth/ConnexionClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Connexion',
  robots: { index: false, follow: true },
};

export default function ConnexionPage() {
  return (
    <main className="mx-auto max-w-md px-m py-l">
      <h1 className="text-2xl font-semibold text-textPrimary">
        Se connecter ou créer un compte
      </h1>
      <p className="mt-xs text-sm text-textTertiary">
        Votre compte est créé automatiquement à votre première connexion.
      </p>
      <div className="mt-l">
        <Suspense>
          <ConnexionClient />
        </Suspense>
      </div>
    </main>
  );
}
