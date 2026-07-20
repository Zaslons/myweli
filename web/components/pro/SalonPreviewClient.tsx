'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import type { Provider } from '../../lib/api/providers';
import { getMyProvider } from '../../lib/api/pro';
import { ProviderView } from '../provider/ProviderView';
import { Button } from '../Button';

/// « Aperçu de ma page » (docs/design/pro-salon-lifecycle.md B4): the owner
/// sees their salon EXACTLY as a client will — the real consumer page
/// component fed from /me/provider (owner-scoped), so drafts stay invisible
/// to everyone else (T51) and no new endpoint exists.
export function SalonPreviewClient() {
  const router = useRouter();
  const [provider, setProvider] = useState<Provider | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(false);
    const me = await getMyProvider();
    if (me.status === 401) {
      router.replace('/pro/connexion');
      return;
    }
    if (me.status !== 200 || !me.profile) {
      setError(true);
      setLoading(false);
      return;
    }
    // The /me/provider payload IS the full provider document; ProProfile is
    // only a narrowed view of it.
    setProvider(me.profile.provider as unknown as Provider);
    setLoading(false);
  }, [router]);

  useEffect(() => {
    load();
  }, [load]);

  if (loading) {
    return <p className="p-l text-textSecondary">Chargement de l’aperçu…</p>;
  }
  if (error || !provider) {
    return (
      <div className="p-l">
        <p role="alert" className="text-error">Impossible de charger l’aperçu.</p>
        <div className="mt-s">
          <Button variant="secondary" onClick={load}>
            Réessayer
          </Button>
        </div>
      </div>
    );
  }

  const draft = provider.status === 'draft';

  return (
    <div>
      {/* The preview banner — the only element a client will NOT see. */}
      <div className="border-b border-border bg-primary px-m py-s text-bodyMedium text-secondary">
        <div className="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-s">
          <span>
            {draft
              ? 'Aperçu — votre salon n’est pas encore en ligne. Voici ce que verront vos clients.'
              : 'Votre salon est en ligne — ceci est votre page publique.'}
          </span>
          <span className="flex gap-m">
            {!draft && provider.slug ? (
              <Link href={`/${provider.slug}`} className="underline">
                Voir la page publique
              </Link>
            ) : null}
            <Link href="/pro" className="underline">
              ← Tableau de bord
            </Link>
          </span>
        </div>
      </div>
      <ProviderView
        provider={provider}
        slug={provider.slug ?? ''}
        preview={draft}
      />
    </div>
  );
}
