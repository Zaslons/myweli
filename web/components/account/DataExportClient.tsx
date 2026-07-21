'use client';

import Link from 'next/link';
import { ErrorState } from '../ErrorState';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import type { Me } from '../../lib/api/account';
import {
  getFavorites,
  getMe,
  listAppointments,
} from '../../lib/api/account';
import type { Appointment } from '../../lib/account/appointments';
import { buildUserDataExport } from '../../lib/account/export';
import { Button } from '../Button';
import { Loading } from '../Loading';

/// « Mes données » (parity 11.2 — the app's data-export screen, web-adapted):
/// profile + rendez-vous + favoris assembled client-side into one JSON,
/// downloadable and copyable.
export function DataExportClient() {
  const router = useRouter();
  const [me, setMe] = useState<Me | null>(null);
  const [appointments, setAppointments] = useState<Appointment[]>([]);
  const [favoriteNames, setFavoriteNames] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [copied, setCopied] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(false);
    const meRes = await getMe();
    if (meRes.status === 401) {
      router.replace('/connexion?returnTo=/mon-compte/donnees');
      return;
    }
    if (meRes.status !== 200 || !meRes.user) {
      setError(true);
      setLoading(false);
      return;
    }
    const [appts, favs] = await Promise.all([
      listAppointments(),
      getFavorites(),
    ]);
    setMe(meRes.user);
    setAppointments(appts.items);
    setFavoriteNames(favs.favorites.map((p) => p.name));
    setLoading(false);
  }, [router]);

  useEffect(() => {
    load();
  }, [load]);

  useEffect(() => {
    if (!copied) return;
    const t = setTimeout(() => setCopied(false), 2000);
    return () => clearTimeout(t);
  }, [copied]);

  if (loading) return <Loading className="mt-l" />;
  if (error || !me) {
    return (
      <div>
        <ErrorState title="Mes données" message="Chargement impossible." onRetry={load} />
      </div>
    );
  }

  const doc = buildUserDataExport({
    me,
    appointments,
    favoriteProviderNames: favoriteNames,
  });
  const json = JSON.stringify(doc, null, 2);

  function download() {
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'myweli-donnees.json';
    a.click();
    URL.revokeObjectURL(url);
  }

  async function copy() {
    await navigator.clipboard.writeText(json);
    setCopied(true);
  }

  return (
    <div className="max-w-2xl">
      <Link href="/mon-compte" className="text-bodyMedium text-textTertiary">
        ← Mon compte
      </Link>
      <h1 className="mt-s text-headlineSmall font-semibold text-textPrimary">
        Mes données
      </h1>
      <p className="mt-xs text-bodyMedium text-textSecondary">
        Une copie de vos données MyWeli : profil, rendez-vous et favoris.
      </p>

      <section className="mt-l rounded-xl border border-border bg-secondary p-l">
        <dl className="space-y-xs text-bodyMedium">
          <div className="flex justify-between gap-m">
            <dt className="text-textTertiary">Profil</dt>
            <dd className="text-textPrimary">{me.email ?? me.phoneNumber}</dd>
          </div>
          <div className="flex justify-between gap-m">
            <dt className="text-textTertiary">Rendez-vous</dt>
            <dd className="text-textPrimary">{appointments.length}</dd>
          </div>
          <div className="flex justify-between gap-m">
            <dt className="text-textTertiary">Favoris</dt>
            <dd className="text-textPrimary">{favoriteNames.length}</dd>
          </div>
        </dl>
        <div className="mt-m flex flex-wrap gap-s">
          <Button onClick={download}>Télécharger (JSON)</Button>
          <Button variant="secondary" onClick={copy}>
            {copied ? 'Copié ✓' : 'Copier'}
          </Button>
          <span role="status" className="sr-only">
            {copied ? 'Données copiées.' : ''}
          </span>
        </div>
      </section>
    </div>
  );
}
