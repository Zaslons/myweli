import type { Metadata } from 'next';
import { Suspense } from 'react';
import { OpenInAppButton } from '../../../components/OpenInAppButton';
import { ProConnexionClient } from '../../../components/pro/ProConnexionClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Espace Pro — Connexion',
  robots: { index: false, follow: false },
};

export default function ProConnexionPage() {
  return (
    <main className="mx-auto max-w-md px-m py-l">
      <h1 className="text-2xl font-semibold text-textPrimary">Espace Pro</h1>
      <p className="mt-xs text-sm text-textTertiary">
        Connectez-vous à votre espace salon.
      </p>
      <div className="mt-l">
        {/* Suspense: the client reads ?motif= via useSearchParams (R5b). */}
        <Suspense fallback={null}>
          <ProConnexionClient />
        </Suspense>
      </div>
      <p className="mt-l text-sm text-textTertiary">
        Pas encore inscrit&nbsp;? Créez votre salon dans l’app MyWeli Pro.
      </p>
      <div className="mt-s">
        <OpenInAppButton />
      </div>
    </main>
  );
}
