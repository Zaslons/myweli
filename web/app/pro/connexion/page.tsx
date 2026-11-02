import type { Metadata } from 'next';
import { AuthFormSkeleton } from '../../../components/auth/AuthFormSkeleton';
import { Suspense } from 'react';
import { ProConnexionClient } from '../../../components/pro/ProConnexionClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Espace Pro — Connexion',
  robots: { index: false, follow: false },
};

/// **No store link here (web-true-sentences.md §5).** Salons sign up on the web:
/// the app sends them here, and « Créer mon compte » is in the form below. There
/// is one pair of store URLs and it is the CLIENT app's, so a « Créez votre salon
/// dans l'app » block would have looped, then opened the wrong app, on the day
/// those URLs were set. A Pro install link needs its own pair.
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
    </main>
  );
}
