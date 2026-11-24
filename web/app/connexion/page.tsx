import type { Metadata } from 'next';
import { Suspense } from 'react';
import { AuthFormSkeleton } from '../../components/auth/AuthFormSkeleton';
import { ConnexionClient } from '../../components/auth/ConnexionClient';
import { signInReasonLine } from '../../lib/auth/sign-in-reason';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Connexion',
  robots: { index: false, follow: true },
};

export default function ConnexionPage({
  searchParams,
}: {
  searchParams: { raison?: string | string[] };
}) {
  // Why it opened, when a known way in says so (consumer-signin-push.md §14.2).
  const reason = signInReasonLine(searchParams.raison);
  return (
    <main className="mx-auto max-w-md px-m py-l">
      <h1 className="text-headlineSmall font-semibold text-textPrimary">
        Se connecter ou créer un compte
      </h1>
      {reason ? (
        <p className="mt-xs text-bodyLarge text-textSecondary">{reason}</p>
      ) : null}
      <p className="mt-xs text-bodyLarge text-textTertiary">
        Votre compte est créé automatiquement à votre première connexion.
      </p>
      <div className="mt-l">
        <Suspense fallback={<AuthFormSkeleton />}>
          <ConnexionClient />
        </Suspense>
      </div>
    </main>
  );
}
