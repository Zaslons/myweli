'use client';

import Link from 'next/link';
import { ErrorState } from '../ErrorState';
import { Loading } from '../Loading';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import type { Provider } from '../../lib/api/providers';
import { getMyProvider } from '../../lib/api/pro';
import { type SalonValidation, previewBanner } from '../../lib/pro/salon-validation';
import { loadFailure, loadFailureMessage, type LoadFailure } from '../../lib/api/load-failure';
import { ProviderView } from '../provider/ProviderView';

/// « Aperçu de ma page » (docs/design/pro-salon-lifecycle.md B4): the owner
/// sees their salon EXACTLY as a client will — the real consumer page
/// component fed from /me/provider (owner-scoped), so drafts stay invisible
/// to everyone else (T51) and no new endpoint exists.
export function SalonPreviewClient() {
  const router = useRouter();
  const [provider, setProvider] = useState<Provider | null>(null);
  /// B0.18 — beside the provider; absent from a server before it (§4.4).
  const [validation, setValidation] = useState<SalonValidation | null | undefined>(undefined);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<LoadFailure | false>(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(false);
    const me = await getMyProvider();
    if (me.status === 401) {
      router.replace('/pro/connexion');
      return;
    }
    if (me.status !== 200 || !me.profile) {
      setError(loadFailure(me.status));
      setLoading(false);
      return;
    }
    // The /me/provider payload IS the full provider document; ProProfile is
    // only a narrowed view of it.
    setProvider(me.profile.provider as unknown as Provider);
    setValidation(me.profile.validation);
    setLoading(false);
  }, [router]);

  useEffect(() => {
    load();
  }, [load]);

  if (loading) {
    return (
      <main className="p-l">
        <Loading label="Chargement de l’aperçu…" />
      </main>
    );
  }
  if (error || !provider) {
    return (
      <main className="p-l">
        <ErrorState
          title="Aperçu du salon"
          message={loadFailureMessage(error, 'Impossible de charger l’aperçu.')}
          onRetry={load}
        />
      </main>
    );
  }

  // **`=== 'draft'` was the wrong question.** A SUSPENDED salon answered
  // `false` here, so its owner's preview rendered the consumer heart and a
  // « Voir la page publique » link — to a page that 404s once Decision C
  // lands. What the banner is really asking is « is this page live? ».
  const live = !provider.status || provider.status === 'active';

  return (
    <div>
      {/* The preview banner — the only element a client will NOT see. A
          landmark (axe `region`): every element belongs to one. */}
      <aside
        aria-label="Aperçu du salon"
        className="border-b border-border bg-primary px-m py-s text-bodyMedium text-secondary"
      >
        <div className="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-s">
          {/* Today's three sentences for a server before B0.18; with it,
              the validation's state (owner, 2026-11-13 —
              docs/design/web-salon-validation.md §4.4). */}
          <span>{previewBanner(provider.status, validation)}</span>
          <span className="flex gap-m">
            {live && provider.slug ? (
              <Link href={`/${provider.slug}`} className="underline">
                Voir la page publique
              </Link>
            ) : null}
            <Link href="/pro" className="underline">
              ← Tableau de bord
            </Link>
          </span>
        </div>
      </aside>
      <ProviderView
        provider={provider}
        slug={provider.slug ?? ''}
        preview={!live}
      />
    </div>
  );
}
