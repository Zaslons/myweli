import type { Metadata } from 'next';
import { AuthFormSkeleton } from '../../../components/auth/AuthFormSkeleton';
import { Suspense } from 'react';
import { OpenInAppButton } from '../../../components/OpenInAppButton';
import { ProConnexionClient } from '../../../components/pro/ProConnexionClient';
import { appStoreUrl } from '../../../lib/appStore';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Espace Pro — Connexion',
  robots: { index: false, follow: false },
};

export default function ProConnexionPage() {
  return (
    <main className="mx-auto max-w-md px-m py-l">
      <h1 className="text-headlineSmall font-semibold text-textPrimary">Espace Pro</h1>
      <p className="mt-xs text-bodyLarge text-textTertiary">
        Connectez-vous à votre espace salon.
      </p>
      <div className="mt-l">
        {/* Suspense: the client reads ?motif= via useSearchParams (R5b). */}
        <Suspense fallback={<AuthFormSkeleton />}>
          <ProConnexionClient />
        </Suspense>
      </div>
      {/* **The same orphan #478 fixed on the homepage, on a page its guard
          never visited.** `OpenInAppButton` renders nothing while the apps are
          unlisted, so this shipped as « Créez votre salon dans l'app MyWeli
          Pro. » with no way to get it — copy and control must appear together
          or not at all.

          NOTE, separate and deliberately not fixed here: there is only ONE pair
          of store URLs (`NEXT_PUBLIC_*_APP_URL`, the CONSUMER app, `ci.myweli`).
          When they are set, this pro page will link a salon owner to the client
          app. That needs a pro-specific pair, not a gate. */}
      {appStoreUrl() ? (
        <>
          <p className="mt-l text-bodyLarge text-textTertiary">
            Pas encore inscrit&nbsp;? Créez votre salon dans l’app MyWeli Pro.
          </p>
          <div className="mt-s">
            <OpenInAppButton />
          </div>
        </>
      ) : null}
    </main>
  );
}
