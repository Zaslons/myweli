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
import {
  EXPORT_COPY_FAILED,
  type ExportSection,
  buildUserDataExport,
  exportFailureMessage,
} from '../../lib/account/export';
import { Button } from '../Button';
import { Loading } from '../Loading';

/// « Mes données » (parity 11.2 — the app's data-export screen, web-adapted):
/// profile + rendez-vous + favoris assembled client-side into one JSON,
/// downloadable and copyable.
///
/// The copy is whole or it is not offered: a read that fails names the
/// missing data and the page offers « Réessayer », never a section emptied
/// by its failure (docs/design/consumer-export-completeness.md).
export function DataExportClient() {
  const router = useRouter();
  const [me, setMe] = useState<Me | null>(null);
  const [appointments, setAppointments] = useState<Appointment[]>([]);
  const [favoriteNames, setFavoriteNames] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [failed, setFailed] = useState<ExportSection[]>([]);
  const [copied, setCopied] = useState(false);
  const [copyFailed, setCopyFailed] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setFailed([]);
    // None of the three throws: a request with no usable answer — no network,
    // or a body cut off on the way — is status 0 (lib/api/network.ts,
    // docs/design/web-consumer-network-failure.md §2), one more failed section.
    const [m, a, f] = await Promise.all([
      getMe(),
      listAppointments(),
      getFavorites(),
    ]);
    if ([m, a, f].some((r) => r.status === 401)) {
      router.replace('/connexion?returnTo=/mon-compte/donnees');
      return;
    }
    const user = m.status === 200 ? m.user ?? null : null;
    const missing: ExportSection[] = [];
    if (!user) missing.push('profile');
    if (a.status !== 200) missing.push('appointments');
    if (f.status !== 200) missing.push('favorites');
    if (!user || missing.length > 0) {
      setFailed(missing);
      setLoading(false);
      return;
    }
    setMe(user);
    setAppointments(a.items);
    setFavoriteNames(f.favorites.map((p) => p.name));
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
  if (failed.length > 0 || !me) {
    return (
      <div>
        <ErrorState
          title="Mes données"
          message={exportFailureMessage(failed)}
          onRetry={load}
        />
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
    setCopyFailed(false);
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'myweli-donnees.json';
    a.click();
    URL.revokeObjectURL(url);
  }

  async function copy() {
    setCopyFailed(false);
    try {
      await navigator.clipboard.writeText(json);
    } catch {
      // Permission, an unfocused page, or no clipboard at all (an insecure
      // origin) — the download needs none of them.
      setCopyFailed(true);
      return;
    }
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
      <p className="mt-xs text-bodyLarge text-textSecondary">
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
        {copyFailed ? (
          <p role="alert" className="mt-s text-bodyMedium text-error">
            {EXPORT_COPY_FAILED}
          </p>
        ) : null}
      </section>
    </div>
  );
}
